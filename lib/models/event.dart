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

  Event({
    this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    DateTime? createdAt,
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
    );
  }
}
