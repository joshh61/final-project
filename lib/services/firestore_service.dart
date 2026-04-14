import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';

/// Handles all Firestore database operations for events.
///
/// This keeps database logic separate from UI code.
/// The UI calls these methods without needing to know
/// how Firestore works internally.
class FirestoreService {
  // Reference to the 'events' collection in Firestore.
  // A "collection" in Firestore is like a table in SQL —
  // it holds multiple documents (rows).
  final CollectionReference _eventsCollection =
      FirebaseFirestore.instance.collection('events');

  /// Adds a new event to Firestore.
  ///
  /// _eventsCollection.add() creates a new document with an
  /// auto-generated ID and stores the map data inside it.
  /// Returns the document ID so we can reference it later.
  Future<String> addEvent(Event event) async {
    final docRef = await _eventsCollection.add(event.toMap());
    return docRef.id;
  }

  /// Returns a real-time stream of all events.
  ///
  /// This is the key Firestore feature — instead of fetching once,
  /// snapshots() returns a Stream that fires every time the collection
  /// changes. So if someone on another phone adds an event, your
  /// app gets notified automatically.
  ///
  /// The .map() transforms each snapshot (raw Firestore data) into
  /// a List<Event> (our Dart objects) using the fromFirestore factory.
  Stream<List<Event>> getEventsStream() {
    return _eventsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Event.fromFirestore(doc))
            .toList());
  }

  /// Deletes an event by its Firestore document ID.
  Future<void> deleteEvent(String eventId) async {
    await _eventsCollection.doc(eventId).delete();
  }

  /// Adds the current user's UID to the event's hypedBy array and increments
  /// hypeCount by 1. Both updates happen in a single Firestore write.
  Future<void> hypeEvent(String eventId, String uid) async {
    await _eventsCollection.doc(eventId).update({
      // arrayUnion adds uid only if not already present — safe to call multiple times.
      'hypedBy': FieldValue.arrayUnion([uid]),
      // increment is atomic on the server — no race conditions.
      'hypeCount': FieldValue.increment(1),
    });
  }

  /// Removes the current user's UID from hypedBy and decrements hypeCount by 1.
  /// Called when the user taps the Hype button a second time to un-hype.
  Future<void> unhypeEvent(String eventId, String uid) async {
    await _eventsCollection.doc(eventId).update({
      // arrayRemove removes the uid from the array (no-op if not present).
      'hypedBy': FieldValue.arrayRemove([uid]),
      'hypeCount': FieldValue.increment(-1),
    });
  }

  // ── RSVP ────────────────────────────────────────────────────────────────────
  //
  // RSVPs use a Firestore subcollection instead of an array field.
  // Structure: events/{eventId}/rsvps/{userId}
  //
  // Why subcollection instead of array?
  //   - Each RSVP document can store extra data (timestamp, name, email)
  //   - No document size limit issues for very popular events
  //   - Easy to query the full attendee list
  //
  // We use Firestore transactions to update rsvpCount atomically alongside
  // creating/deleting the subcollection document — so the count never drifts.

  /// RSVP the user to an event. Stores a document in the rsvps subcollection
  /// and increments rsvpCount on the event document in one atomic transaction.
  Future<void> rsvpEvent(
    String eventId,
    String uid, {
    String? displayName,
    String? email,
  }) async {
    final eventRef = _eventsCollection.doc(eventId);
    // A subcollection reference — Firestore creates it automatically on first write.
    final rsvpRef = eventRef.collection('rsvps').doc(uid);

    // runTransaction groups multiple reads/writes so they succeed or fail together.
    // This prevents the count and the subcollection document from getting out of sync.
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final rsvpDoc = await transaction.get(rsvpRef);
      if (rsvpDoc.exists) return; // already RSVP'd — nothing to do

      // Create the RSVP document for this user.
      transaction.set(rsvpRef, {
        'rsvpdAt': FieldValue.serverTimestamp(), // server time, not device time
        'displayName': displayName,
        'email': email,
      });
      // Increment the count on the event document.
      transaction.update(eventRef, {'rsvpCount': FieldValue.increment(1)});
    });
  }

  /// Remove the user's RSVP. Deletes the subcollection document and
  /// decrements rsvpCount in one atomic transaction.
  Future<void> unrsvpEvent(String eventId, String uid) async {
    final eventRef = _eventsCollection.doc(eventId);
    final rsvpRef = eventRef.collection('rsvps').doc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final rsvpDoc = await transaction.get(rsvpRef);
      if (!rsvpDoc.exists) return; // not RSVP'd — nothing to do

      transaction.delete(rsvpRef);
      transaction.update(eventRef, {'rsvpCount': FieldValue.increment(-1)});
    });
  }

  /// Returns true if the given user has RSVP'd to the event.
  /// Used on screen open to seed the initial button state.
  Future<bool> checkUserRsvp(String eventId, String uid) async {
    final doc = await _eventsCollection
        .doc(eventId)
        .collection('rsvps')
        .doc(uid)
        .get();
    return doc.exists;
  }

  /// Real-time stream of all attendees for an event.
  /// Each document in the stream has: rsvpdAt, displayName, email.
  Stream<QuerySnapshot> getRsvpsStream(String eventId) {
    return _eventsCollection
        .doc(eventId)
        .collection('rsvps')
        .orderBy('rsvpdAt')
        .snapshots();
  }

  // ── Favorites ────────────────────────────────────────────────────────────────
  //
  // Favorites are stored in a per-user subcollection:
  //   users/{userId}/favorites/{eventId}
  //
  // Each document stores a snapshot of the event data at save time plus a
  // savedAt timestamp. Using the eventId as the document ID means saving the
  // same event twice is a no-op (set() overwrites cleanly).

  // Shorthand reference to a user's favorites subcollection.
  CollectionReference _favoritesRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('favorites');

  /// Saves an event to the user's favorites. Stores the full event snapshot
  /// so the favorites list can be displayed without re-querying the events collection.
  Future<void> saveEvent(String uid, Event event) async {
    await _favoritesRef(uid).doc(event.id).set({
      ...event.toMap(), // spread all event fields into the favorites document
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes an event from the user's favorites.
  Future<void> unsaveEvent(String uid, String eventId) async {
    await _favoritesRef(uid).doc(eventId).delete();
  }

  /// One-time check — returns true if the user has saved this event.
  /// Used to seed the initial bookmark button state on screen open.
  Future<bool> checkEventSaved(String uid, String eventId) async {
    final doc = await _favoritesRef(uid).doc(eventId).get();
    return doc.exists;
  }

  /// Real-time stream of the set of event IDs the user has saved.
  /// The EventsScreen listens to this to know which cards to mark as saved.
  Stream<Set<String>> getSavedEventIdsStream(String uid) {
    return _favoritesRef(uid).snapshots().map(
          // Each document's ID is the eventId — collect them into a Set for O(1) lookup.
          (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
        );
  }

  // ── Reviews ──────────────────────────────────────────────────────────────────
  //
  // Reviews use a subcollection: events/{eventId}/reviews/{userId}
  // One document per user — re-submitting overwrites the previous review.
  //
  // The event document caches averageRating and reviewCount so cards can
  // display ratings without querying the subcollection. We maintain a
  // ratingSum field (not exposed on Event) to recompute the average cheaply
  // when a user updates their existing review.

  /// Submits or updates a star rating (1–5) with an optional text comment.
  /// Uses a transaction so averageRating/reviewCount on the event document
  /// stay in sync with the subcollection even under concurrent writes.
  Future<void> submitReview(
    String eventId,
    String uid,
    int rating, {
    String comment = '',
  }) async {
    final eventRef = _eventsCollection.doc(eventId);
    final reviewRef = eventRef.collection('reviews').doc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final reviewSnap = await transaction.get(reviewRef);
      final eventSnap = await transaction.get(eventRef);

      final eventData = eventSnap.data() as Map<String, dynamic>? ?? {};
      final currentSum = (eventData['ratingSum'] ?? 0) as num;
      final currentCount = (eventData['reviewCount'] ?? 0) as num;

      final int newSum;
      final int newCount;

      if (reviewSnap.exists) {
        // User is updating an existing review — adjust sum without changing count.
        final oldRating = (reviewSnap.data() as Map<String, dynamic>)['rating'] as int;
        newSum = currentSum.toInt() - oldRating + rating;
        newCount = currentCount.toInt();
      } else {
        // First review from this user.
        newSum = currentSum.toInt() + rating;
        newCount = currentCount.toInt() + 1;
      }

      final double newAverage = newCount > 0 ? newSum / newCount : 0.0;

      transaction.set(reviewRef, {
        'rating': rating,
        'comment': comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(eventRef, {
        'ratingSum': newSum,
        'reviewCount': newCount,
        'averageRating': newAverage,
      });
    });
  }

  /// Returns the current user's review document, or null if they haven't reviewed.
  Future<Map<String, dynamic>?> getUserReview(String eventId, String uid) async {
    final doc = await _eventsCollection
        .doc(eventId)
        .collection('reviews')
        .doc(uid)
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// Real-time stream of all reviews for an event, newest first.
  Stream<QuerySnapshot> getReviewsStream(String eventId) {
    return _eventsCollection
        .doc(eventId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
