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
}
