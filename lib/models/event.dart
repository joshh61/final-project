import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a campus event with a location on the map.
///
/// This class handles conversion to/from Firestore documents.
/// Firestore stores data as Map<String, dynamic> (like JSON objects),
/// so we need methods to convert between our Dart object and that format.
class Event {
  // Firestore document ID — assigned by Firestore when the doc is created.
  // Nullable because a NEW event doesn't have an ID yet (Firestore gives it one).
  final String? id;

  final String name;
  final String description;
  final double latitude;
  final double longitude;

  // When the event was created. Firestore has its own Timestamp type,
  // but we convert it to Dart's DateTime for easier use in the app.
  final DateTime createdAt;

  // How many unique users have hyped this event.
  final int hypeCount;

  // The list of Firebase Auth UIDs that have already hyped this event.
  // We use this to prevent the same user from hyping more than once.
  // Stored as an array field in Firestore.
  final List<String> hypedBy;

  // How many users have RSVP'd to this event.
  // The actual attendee list is stored in a Firestore subcollection:
  //   events/{eventId}/rsvps/{userId}
  // We keep a count here so we can display it without reading the subcollection.
  final int rsvpCount;

  // Cached average star rating (1–5). Recomputed and stored on the event
  // document each time a review is submitted via a Firestore transaction.
  final double averageRating;

  // Number of reviews submitted. Kept alongside averageRating so the card
  // can show "4.2 ★ (12)" without reading the reviews subcollection.
  final int reviewCount;

  // Optional Firebase Storage download URL for a photo attached to this event.
  final String? imageUrl;

  // Whether the event is free to attend. Defaults to true.
  // Stored as a boolean field in Firestore; old docs without this field
  // are treated as free (the ?? true fallback in fromFirestore).
  final bool isFree;

  Event({
    this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    DateTime? createdAt,
    this.hypeCount = 0,
    this.hypedBy = const [],
    this.rsvpCount = 0,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.imageUrl,
    this.isFree = true,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Converts this Event object into a Map that Firestore can store.
  /// This is like serializing to JSON.
  ///
  /// Note: we DON'T include 'id' here because Firestore uses the
  /// document ID separately — it's not stored inside the document itself.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'hypeCount': hypeCount,
      'hypedBy': hypedBy,
      'rsvpCount': rsvpCount,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'isFree': isFree,
    };
  }

  /// Creates an Event object from a Firestore document snapshot.
  /// This is like deserializing from JSON.
  ///
  /// 'doc' is a Firestore DocumentSnapshot — it has:
  ///   - doc.id → the document's unique ID
  ///   - doc.data() → the actual fields as a Map<String, dynamic>
  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      hypeCount: (data['hypeCount'] ?? 0) as int,
      hypedBy: List<String>.from(data['hypedBy'] ?? []),
      rsvpCount: (data['rsvpCount'] ?? 0) as int,
      averageRating: (data['averageRating'] ?? 0).toDouble(),
      reviewCount: (data['reviewCount'] ?? 0) as int,
      imageUrl: data['imageUrl'] as String?,
      isFree: (data['isFree'] as bool?) ?? true,
    );
  }
}
