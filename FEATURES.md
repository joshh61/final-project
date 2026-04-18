# Campus Vibes — Complete Feature Tutorial

**Who this is for:** Anyone building or studying the Campus Vibes Flutter app with
little to no Dart experience. Every concept is explained from the ground up.

**What this covers:** Every file, every feature, and every major code decision — from
the data model all the way through to live GPS walking navigation.

**How to read it:** Work top to bottom. Each section builds on the one before it.
Code blocks contain the real code from the project, with comments explaining every line.

---

## Table of Contents

1. [Dart Basics You Need First](#1-dart-basics-you-need-first)
2. [Project Setup — pubspec.yaml](#2-project-setup--pubspecyaml)
3. [The Event Model](#3-the-event-model)
4. [FirestoreService — The Database Layer](#4-firestoreservice--the-database-layer)
5. [App Entry Point — main.dart](#5-app-entry-point--maindart)
6. [Home Screen — Bottom Navigation](#6-home-screen--bottom-navigation)
7. [Events Screen — The List View](#7-events-screen--the-list-view)
8. [Event Detail Screen](#8-event-detail-screen)
9. [Calendar Screen](#9-calendar-screen)
10. [Live Navigation](#10-live-navigation)

---

## 1. Dart Basics You Need First

Before touching any file, here are the Dart concepts that appear everywhere in this project.
You will see these constantly — understanding them unlocks everything else.

### Variables and Types

```dart
// A "type" tells Dart what kind of data a variable holds.

String name = "Campus Vibes";   // String = text
int count   = 5;                 // int = whole number (no decimals)
double lat  = 26.3036;           // double = number with decimals
bool isOpen = true;              // bool = true or false

// The ? after a type means the variable CAN be null (empty/missing).
// Without ?, Dart guarantees the variable always has a value.
String? nickname;   // this is allowed to be null
String realName;    // this MUST always have a value — Dart won't compile if it might be null
```

### final vs var

```dart
// final = set once, never changes after that.
// Use final for anything you don't plan to reassign.
final String appName = "Campus Vibes"; // can't do appName = "Other" later

// var = can change at any time.
var count = 0;
count = 1; // perfectly fine
```

### Functions and async/await

```dart
// A regular function runs top to bottom and returns immediately.
int add(int a, int b) {
  return a + b;
}

// An async function can "pause" while waiting for slow work (network, GPS, database).
// Instead of freezing the whole app, Dart suspends just this function.
// await = "wait here for this to finish before moving to the next line."
// Future<String> = "this function will eventually give back a String"
Future<String> fetchEventName() async {
  final result = await someSlowNetworkCall(); // pauses HERE, app keeps running
  return result;                              // resumes here after the call finishes
}
```

### The ? . and ! operators

```dart
// ?. = "only call this if the value is not null, otherwise give back null"
String? name = null;
int? length = name?.length; // safe — gives null instead of crashing

// ! = "I promise this is not null right now" (crashes if you're wrong)
String definitelyHasValue = name!; // throws an error if name is null

// ?? = "if this is null, use the value on the right instead"
String display = name ?? "Unknown"; // "Unknown" if name is null
```

### Lists, Maps, and Sets

```dart
// List = ordered collection. Like an array.
List<String> names = ["Alice", "Bob", "Carlos"];
names[0]; // "Alice" — index starts at 0

// Map = key → value pairs. Like a dictionary.
Map<String, int> ages = {"Alice": 20, "Bob": 22};
ages["Alice"]; // 20

// Set = unordered collection with NO duplicates. .contains() is very fast.
Set<String> savedIds = {"abc123", "xyz789"};
savedIds.contains("abc123"); // true — O(1), instant regardless of size
```

### StatelessWidget vs StatefulWidget

```dart
// StatelessWidget = displays fixed data. No memory of changes.
// Use when the screen never updates on its own.
class MyLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text("Hello");
  }
}

// StatefulWidget = has STATE — data that changes over time.
// When setState() is called, Flutter rebuilds the widget with new data.
// Use when the screen needs to react to taps, streams, or async results.
class MyCounter extends StatefulWidget {
  @override
  State<MyCounter> createState() => _MyCounterState();
}

class _MyCounterState extends State<MyCounter> {
  int count = 0; // this is the "state" — it can change

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => count++), // rebuild with new count
      child: Text("$count"),
    );
  }
}
```

### Streams and StreamSubscription

```dart
// A Stream is a continuous sequence of values over time.
// Think of it like a TV channel — it keeps broadcasting new values.
// Firestore uses Streams to send your app live updates whenever the database changes.

Stream<int> countStream; // a stream that emits integers over time

// StreamSubscription = the "remote control" for a stream.
// .listen() starts watching the stream and gives you each value as it arrives.
// You MUST cancel the subscription in dispose() or the stream keeps running forever.
StreamSubscription<int>? subscription;

subscription = countStream.listen((value) {
  print(value); // runs every time the stream emits a new value
});

// In dispose():
subscription?.cancel(); // stop listening, free resources
```

---

## 2. Project Setup — pubspec.yaml

`pubspec.yaml` is the configuration file for the entire Flutter project.
It lists the app's name, version, and every external package ("dependency") the app uses.

**Where:** root of the project — `pubspec.yaml`
**When:** edit this file whenever you add a new package or asset (image, font, etc.)
**Why:** Flutter won't know a package exists until it's listed here. After editing,
run `flutter pub get` to download any new packages.

```yaml
name: final_project
description: "Campus Vibes — UTRGV campus event discovery app"

environment:
  sdk: ^3.11.0   # minimum Dart version required

dependencies:
  flutter:
    sdk: flutter

  # --- MAP ---
  # mapbox_maps_flutter: renders the interactive campus map and GPS puck
  mapbox_maps_flutter: 2.18.0

  # --- FIREBASE ---
  # Firebase is Google's cloud backend. We use three parts of it:
  firebase_core: ^4.4.0       # required base package — always needed with Firebase
  cloud_firestore: ^6.1.2     # the database (stores events, RSVPs, reviews, etc.)
  firebase_auth: ^6.1.4       # handles login/logout with email + password

  # --- LOCATION ---
  # geolocator: reads the device GPS and checks/requests location permission
  geolocator: ^10.1.0

  # --- NETWORKING ---
  # http: makes HTTP GET requests to the Mapbox Directions API
  http: ^1.1.0

  # --- DATE FORMATTING ---
  # intl: formats DateTime objects into readable strings like "Apr 14, 2026 – 7:30 PM"
  intl: ^0.20.2

  # --- SHARING ---
  # share_plus: opens the native iOS/Android share sheet so users can
  # send event info via Messages, WhatsApp, email, etc.
  share_plus: ^10.1.4

  # --- CALENDAR ---
  # table_calendar: renders a monthly calendar grid with dot indicators
  # on days that have events. Building this from scratch would take days.
  table_calendar: ^3.1.2

flutter:
  uses-material-design: true

  # assets: every image file the app loads at runtime must be listed here.
  # Without registering an asset, rootBundle.load() will throw an error.
  assets:
    - assets/pic1a.png   # custom GPS puck icon (default)
    - assets/pic1b.png   # custom GPS puck icon (alternate)
```

---

## 3. The Event Model

**What:** A Dart class that represents one campus event.
**Where:** `lib/models/event.dart`
**Why:** Firestore stores data as raw key-value maps (like JSON). The Event class
gives us a clean, typed Dart object to work with instead of raw maps everywhere.
We convert between the two using `toMap()` (Dart → Firestore) and `fromFirestore()` (Firestore → Dart).

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
// We import Firestore so we can use Timestamp (Firestore's date type)
// and DocumentSnapshot (one document that Firestore sent back to us).

class Event {

  // --- FIELDS ---
  // Every event has these properties. "final" means once the Event is created,
  // these values cannot change — you would create a new Event object instead.

  final String? id;
  // String? — the ? means this CAN be null.
  // Why nullable? Firestore auto-generates the document ID when you save an event.
  // A brand-new event that hasn't been saved yet doesn't have an ID yet.

  final String name;        // the event title, e.g. "IEEE Game Night"
  final String description; // longer text describing the event
  final double latitude;    // GPS coordinate — where on Earth (north/south)
  final double longitude;   // GPS coordinate — where on Earth (east/west)
  final DateTime createdAt; // when this event was created/posted

  // --- HYPE FIELDS ---
  // "Hyping" is like a campus upvote. One hype per user, toggleable.

  final int hypeCount;
  // int = whole number. Counts how many unique users have hyped this event.
  // Stored directly on the event document so we can show it on cards
  // without reading every user's data.

  final List<String> hypedBy;
  // List<String> = a list of text values.
  // Stores the Firebase Auth UID of every user who has hyped.
  // We check .contains(uid) before allowing a hype to prevent duplicates.
  // Firestore stores this as an array field.

  // --- RSVP FIELDS ---
  final int rsvpCount;
  // How many users have RSVP'd. Stored here as a quick-access counter.
  // The actual attendee list lives in a subcollection: events/{id}/rsvps/{userId}

  // --- RATING FIELDS ---
  final double averageRating;
  // double because averages have decimals (e.g. 4.2).
  // Cached here so event cards can show the rating without reading all reviews.
  // Recomputed every time someone submits or updates a review.

  final int reviewCount;
  // How many reviews exist. Shown alongside the average: "4.2 ★ (12 reviews)"

  // --- CONSTRUCTOR ---
  // The constructor is how you create an Event object.
  // "required" = caller MUST provide this value.
  // "this.field = defaultValue" = optional, uses the default if not provided.
  Event({
    this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    DateTime? createdAt,        // optional — defaults to right now if not given
    this.hypeCount    = 0,
    this.hypedBy      = const [], // const [] = an immutable empty list
    this.rsvpCount    = 0,
    this.averageRating = 0.0,
    this.reviewCount  = 0,
  }) : createdAt = createdAt ?? DateTime.now();
  // The `: createdAt = ...` part runs after the constructor body.
  // ?? means "use createdAt if provided, otherwise use DateTime.now()".

  // --- toMap() ---
  // Converts this Event object into a Map so Firestore can store it.
  // A Map<String, dynamic> is like a JSON object: keys are Strings,
  // values can be any type.
  // Note: we do NOT include 'id' because Firestore uses document ID separately.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      // Firestore has its own Timestamp type — we convert from Dart's DateTime.
      'hypeCount': hypeCount,
      'hypedBy': hypedBy,
      'rsvpCount': rsvpCount,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
    };
  }

  // --- fromFirestore() ---
  // A factory constructor that builds an Event from a Firestore document.
  // "factory" = a special constructor that can do logic before returning the object.
  // DocumentSnapshot = one document (row) returned from Firestore.
  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // doc.data() returns the raw field map. We cast it to the type we know it is.

    return Event(
      id: doc.id,
      // doc.id = the Firestore document ID (auto-generated, unique string)

      name: data['name'] ?? '',
      // data['name'] reads the 'name' field. ?? '' means "use empty string if missing"
      // This protects against old documents that don't have every field yet.

      description: data['description'] ?? '',
      latitude:  (data['latitude']  ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      // .toDouble() converts int or double to double — Firestore might store either.

      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      // If the field exists, convert Firestore Timestamp → Dart DateTime.
      // Otherwise default to now.

      hypeCount:     (data['hypeCount']     ?? 0) as int,
      hypedBy:       List<String>.from(data['hypedBy'] ?? []),
      // List<String>.from() converts a dynamic list to a typed List<String>.
      rsvpCount:     (data['rsvpCount']     ?? 0) as int,
      averageRating: (data['averageRating'] ?? 0).toDouble(),
      reviewCount:   (data['reviewCount']   ?? 0) as int,
    );
  }
}
```

---

## 4. FirestoreService — The Database Layer

**What:** A single class that contains every method for reading and writing to Firestore.
**Where:** `lib/services/firestore_service.dart`
**Why:** Keeping all database logic in one place means the UI files never need to know
how Firestore works internally. If we ever change databases, we only edit this one file.

### Key Firestore Concepts

```
Firestore is a NoSQL cloud database organized like this:

Collection            ← like a SQL table
  └── Document        ← like a SQL row (has a unique ID)
        ├── field: value
        ├── field: value
        └── Subcollection   ← a collection inside a document
              └── Document
```

### The Complete FirestoreService

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';

class FirestoreService {

  // A CollectionReference points to the 'events' collection in Firestore.
  // Think of it as a handle to that "table" — we use it for every events query.
  final CollectionReference _eventsCollection =
      FirebaseFirestore.instance.collection('events');


  // ── EVENTS ──────────────────────────────────────────────────────────────────

  // addEvent — saves a brand new event to Firestore.
  // .add() creates a new document with a Firestore-generated ID.
  // Returns the new document's ID so we can reference it later.
  Future<String> addEvent(Event event) async {
    final docRef = await _eventsCollection.add(event.toMap());
    return docRef.id;
  }

  // getEventsStream — returns a live stream of all events.
  // .snapshots() fires every time the collection changes — new event added,
  // existing event updated, event deleted. Your UI rebuilds automatically.
  // This is Firestore's "real-time" superpower.
  Stream<List<Event>> getEventsStream() {
    return _eventsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Event.fromFirestore(doc))
            .toList());
    // .map() transforms the raw snapshot into a List<Event> using our factory.
  }

  // deleteEvent — removes an event by its document ID.
  Future<void> deleteEvent(String eventId) async {
    await _eventsCollection.doc(eventId).delete();
  }


  // ── HYPE ────────────────────────────────────────────────────────────────────

  // hypeEvent — adds the user's UID to the hypedBy array and increments hypeCount.
  // Both happen in one write — they are always in sync.
  Future<void> hypeEvent(String eventId, String uid) async {
    await _eventsCollection.doc(eventId).update({
      'hypedBy':   FieldValue.arrayUnion([uid]),
      // arrayUnion adds uid ONLY if it's not already in the array.
      // Safe to call multiple times — never creates duplicates.
      'hypeCount': FieldValue.increment(1),
      // increment(1) is atomic on the server. Even if two users hype at the
      // exact same millisecond, both increments are counted correctly.
    });
  }

  // unhypeEvent — removes the user's UID and decrements hypeCount.
  Future<void> unhypeEvent(String eventId, String uid) async {
    await _eventsCollection.doc(eventId).update({
      'hypedBy':   FieldValue.arrayRemove([uid]),
      // arrayRemove removes uid from the array. No-op if uid isn't there.
      'hypeCount': FieldValue.increment(-1),
    });
  }


  // ── RSVPs ────────────────────────────────────────────────────────────────────
  //
  // RSVPs are stored in a subcollection: events/{eventId}/rsvps/{userId}
  // One document per user. We use a transaction so the count and the
  // subcollection document always update together — never out of sync.

  // rsvpEvent — creates the user's RSVP document and increments rsvpCount.
  Future<void> rsvpEvent(
    String eventId,
    String uid, {
    String? displayName, // optional — stored so attendee list can show real names
    String? email,
  }) async {
    final eventRef = _eventsCollection.doc(eventId);
    final rsvpRef  = eventRef.collection('rsvps').doc(uid);
    // Using uid as the document ID means one RSVP per user — can't RSVP twice.

    // runTransaction groups reads and writes so they succeed or fail together.
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final rsvpDoc = await transaction.get(rsvpRef); // read first (required by Firestore)
      if (rsvpDoc.exists) return;                     // already RSVP'd — do nothing

      transaction.set(rsvpRef, {
        'rsvpdAt':     FieldValue.serverTimestamp(), // use server time, not device time
        'displayName': displayName,
        'email':       email,
      });
      transaction.update(eventRef, {'rsvpCount': FieldValue.increment(1)});
    });
  }

  // unrsvpEvent — deletes the RSVP document and decrements rsvpCount.
  Future<void> unrsvpEvent(String eventId, String uid) async {
    final eventRef = _eventsCollection.doc(eventId);
    final rsvpRef  = eventRef.collection('rsvps').doc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final rsvpDoc = await transaction.get(rsvpRef);
      if (!rsvpDoc.exists) return; // not RSVP'd — do nothing

      transaction.delete(rsvpRef);
      transaction.update(eventRef, {'rsvpCount': FieldValue.increment(-1)});
    });
  }

  // checkUserRsvp — one-time read. Returns true if the user has RSVP'd.
  Future<bool> checkUserRsvp(String eventId, String uid) async {
    final doc = await _eventsCollection
        .doc(eventId).collection('rsvps').doc(uid).get();
    return doc.exists;
  }

  // getRsvpsStream — live stream of all attendee documents, oldest RSVP first.
  Stream<QuerySnapshot> getRsvpsStream(String eventId) {
    return _eventsCollection
        .doc(eventId).collection('rsvps')
        .orderBy('rsvpdAt')
        .snapshots();
  }


  // ── FAVORITES ────────────────────────────────────────────────────────────────
  //
  // Favorites are stored per-user: users/{userId}/favorites/{eventId}
  // Using eventId as the document ID means saving the same event twice
  // is a no-op — set() silently overwrites the existing document.

  // Shorthand reference to a user's favorites subcollection.
  // Returns the CollectionReference without repeating the full path everywhere.
  CollectionReference _favoritesRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('favorites');

  // saveEvent — stores the full event snapshot in favorites.
  // The spread operator (...) copies all fields from event.toMap() into this document.
  Future<void> saveEvent(String uid, Event event) async {
    await _favoritesRef(uid).doc(event.id).set({
      ...event.toMap(),
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unsaveEvent(String uid, String eventId) async {
    await _favoritesRef(uid).doc(eventId).delete();
  }

  Future<bool> checkEventSaved(String uid, String eventId) async {
    final doc = await _favoritesRef(uid).doc(eventId).get();
    return doc.exists;
  }

  // getSavedEventIdsStream — live stream of the user's saved event IDs.
  // Returns Set<String> so checking if an event is saved is O(1) — instant.
  // The EventsScreen listens to this to know which card bookmark icons to fill in.
  Stream<Set<String>> getSavedEventIdsStream(String uid) {
    return _favoritesRef(uid).snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
      // Each document's ID is the eventId — collect them into a Set.
    );
  }


  // ── REVIEWS ──────────────────────────────────────────────────────────────────
  //
  // Reviews: events/{eventId}/reviews/{userId}
  // One review per user. Re-submitting overwrites the previous review.
  //
  // We store ratingSum on the event document (not exposed in the Event model).
  // This lets us recompute the average correctly when a user changes their rating:
  //   newAverage = (oldSum - oldRating + newRating) / reviewCount
  // Without ratingSum we couldn't do this without reading all reviews.

  // submitReview — writes the review and updates averageRating on the event atomically.
  Future<void> submitReview(
    String eventId,
    String uid,
    int rating, {
    String comment = '',
  }) async {
    final eventRef  = _eventsCollection.doc(eventId);
    final reviewRef = eventRef.collection('reviews').doc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final reviewSnap = await transaction.get(reviewRef);
      final eventSnap  = await transaction.get(eventRef);

      final eventData    = eventSnap.data() as Map<String, dynamic>? ?? {};
      final currentSum   = (eventData['ratingSum']   ?? 0) as num;
      final currentCount = (eventData['reviewCount'] ?? 0) as num;

      final int newSum;
      final int newCount;

      if (reviewSnap.exists) {
        // User is updating an existing review — adjust sum, keep count the same.
        final oldRating = (reviewSnap.data() as Map<String, dynamic>)['rating'] as int;
        newSum   = currentSum.toInt() - oldRating + rating;
        newCount = currentCount.toInt();
      } else {
        // First review from this user.
        newSum   = currentSum.toInt() + rating;
        newCount = currentCount.toInt() + 1;
      }

      final double newAverage = newCount > 0 ? newSum / newCount : 0.0;

      transaction.set(reviewRef, {
        'rating':    rating,
        'comment':   comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(eventRef, {
        'ratingSum':     newSum,
        'reviewCount':   newCount,
        'averageRating': newAverage,
      });
    });
  }

  // getUserReview — returns the user's existing review data, or null if none.
  Future<Map<String, dynamic>?> getUserReview(String eventId, String uid) async {
    final doc = await _eventsCollection
        .doc(eventId).collection('reviews').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  // getReviewsStream — live stream of all reviews for an event, newest first.
  Stream<QuerySnapshot> getReviewsStream(String eventId) {
    return _eventsCollection
        .doc(eventId).collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
```

---

## 5. App Entry Point — main.dart

**What:** The file that starts the entire app. Sets up Firebase, the Mapbox token,
and decides whether to show the login screen or the main app based on auth state.
Also contains `MapScreen` — the interactive campus map.
**Where:** `lib/main.dart`
**When:** Runs first, before anything else.

```dart
void main() async {
  // WidgetsFlutterBinding.ensureInitialized() must be called first in any app
  // that does async work before runApp(). It connects Flutter's widget system
  // to the underlying platform (iOS/Android).
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase. Must happen before any Firebase calls.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set the Mapbox token. Must happen before any MapWidget is created.
  MapboxOptions.setAccessToken("pk.your_token_here");

  runApp(MyApp()); // hand control to Flutter
}
```

### Auth Gate — Who Sees What

```dart
// StreamBuilder listens to Firebase auth state changes.
// It rebuilds automatically when the user logs in or out.
home: StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(),
  // User? = either a logged-in User object, or null (not logged in)

  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
      // Still loading auth state — show a spinner
    }

    if (snapshot.hasData) {
      return HomeScreen(); // logged in → go to the main app
    }

    return LoginScreen(); // not logged in → go to login
  },
),
```

### MapScreen — The Campus Map

The map screen shows a Mapbox map centered on campus. Event locations appear as
blue circles. Tapping a circle opens that event's detail screen. Tapping empty
map space lets the user create a new event at that location.

```dart
class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleManager;
  // CircleAnnotationManager handles drawing and tapping circle markers on the map.

  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription? _eventsSubscription;
  final Map<String, Event> _circleToEvent = {};
  // Map<String, Event> = dictionary from circle annotation ID → Event object.
  // When a circle is tapped, we look up which Event it represents using this map.

  // Campus bounds — the map won't scroll outside this box.
  static const double utrgvCenterLat = 26.3050;
  static const double utrgvCenterLng = -98.1740;

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Lock the camera to campus — prevents users from scrolling to Tokyo.
    await mapboxMap.setBounds(CameraBoundsOptions(...));

    // Create the manager that will draw circle markers.
    _circleManager = await mapboxMap.annotations.createCircleAnnotationManager();

    // When a circle is tapped, find the matching Event and open its detail screen.
    _circleManager?.tapEvents(
      onTap: (circle) {
        final event = _circleToEvent[circle.id];
        if (event != null) {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)));
        }
      },
    );

    // Listen to Firestore — redraw all markers whenever the events collection changes.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _redrawMarkers(events);
    });
  }

  Future<void> _redrawMarkers(List<Event> events) async {
    await _circleManager!.deleteAll(); // clear old markers first
    _circleToEvent.clear();

    for (final event in events) {
      final circle = await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(event.longitude, event.latitude)),
          circleColor: Colors.blue.toARGB32(), // toARGB32() converts Flutter Color to int
          circleRadius: 12.0,
        ),
      );
      _circleToEvent[circle.id] = event; // register for tap lookup
    }
  }
}
```

---

## 6. Home Screen — Bottom Navigation

**What:** The shell screen that holds the bottom navigation bar and switches between
the three main tabs: Events list, Map, and Calendar.
**Where:** `lib/screens/home_screen.dart`
**Why:** Putting the nav bar here means we swap only the body widget when tabs change —
we don't rebuild the whole screen tree.

```dart
import 'package:flutter/material.dart';
import 'event_screen.dart';
import 'calendar_screen.dart';
import '../main.dart'; // imports MapScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0; // which tab is active (0 = Events, 1 = Map, 2 = Calendar)

  // The three screens. They are created once and reused — not rebuilt on every tab tap.
  final List<Widget> _screens = [
    const EventsScreen(),
    const MapScreen(),
    const CalendarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all three screens alive in the background.
      // Without this, switching tabs would lose scroll position and reload data.
      body: _screens[_currentIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor:   Colors.orange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        // setState() with the new index triggers a rebuild, which swaps the body.

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event),          label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.map),             label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month),  label: 'Calendar'),
        ],
      ),
    );
  }
}
```

---

## 7. Events Screen — The List View

**What:** A scrollable list of all campus events, organized into three sections:
My Favorites, Popular (hypeCount ≥ 1), and All Events.
**Where:** `lib/screens/event_screen.dart`
**Why StatefulWidget:** The screen listens to two live Firestore streams simultaneously
(all events + the user's saved IDs). It must store and update that data as it arrives.

### The State Class

```dart
class _EventsScreenState extends State<EventsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  List<Event> _allEvents   = [];    // all events from Firestore, sorted by hype
  Set<String> _savedEventIds = {};  // event IDs the current user has bookmarked
  bool _loading = true;             // true until the first batch of events arrives

  // StreamSubscription = the "ticket" to a live stream.
  // Keep both so we can cancel them in dispose() and prevent memory leaks.
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<Set<String>>? _savedSubscription;

  @override
  void initState() {
    super.initState();
    // initState() runs ONCE when this widget first appears on screen.

    // Stream 1: all events
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      // Sort by hype count client-side — highest hype first.
      // We sort here instead of using Firestore orderBy('hypeCount') because
      // orderBy EXCLUDES documents that don't have the field at all. Old events
      // without hypeCount would silently disappear. Client sort is safer.
      events.sort((a, b) => b.hypeCount.compareTo(a.hypeCount));
      setState(() {
        _allEvents = events;
        _loading   = false;
      });
    });

    // Stream 2: the user's saved event IDs
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _savedSubscription =
          _firestoreService.getSavedEventIdsStream(uid).listen((ids) {
        setState(() => _savedEventIds = ids);
      });
    }
  }

  @override
  void dispose() {
    // Always cancel subscriptions when the widget is destroyed.
    // If you skip this, the streams keep running and call setState on a
    // widget that no longer exists — which crashes the app.
    _eventsSubscription?.cancel();
    _savedSubscription?.cancel();
    super.dispose();
  }

  // _toggleSave is called when the user taps a bookmark icon on any card.
  // No setState needed — the stream fires and rebuilds automatically.
  Future<void> _toggleSave(Event event) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || event.id == null) return;

    if (_savedEventIds.contains(event.id)) {
      await _firestoreService.unsaveEvent(uid, event.id!);
    } else {
      await _firestoreService.saveEvent(uid, event);
    }
  }
```

### Building the Three Sections

```dart
  @override
  Widget build(BuildContext context) {
    // Split the sorted list into three groups.
    final savedEvents = _allEvents.where((e) => _savedEventIds.contains(e.id)).toList();
    final popular     = _allEvents.where((e) => e.hypeCount >= 1).toList();
    final regular     = _allEvents.where((e) => e.hypeCount < 1).toList();
    // .where() filters a list — like SQL WHERE. Returns a new iterable.
    // .toList() converts that iterable into a concrete List.

    // Build one flat list of widgets: section headers interleaved with cards.
    // A single ListView renders them all in one scrollable column.
    final List<Widget> items = [];

    if (savedEvents.isNotEmpty) {
      items.add(const _SectionHeader(icon: Icons.bookmark, label: 'My Favorites'));
      for (final e in savedEvents) {
        items.add(_EventCard(event: e, isSaved: true, onSaveToggled: () => _toggleSave(e)));
      }
    }

    if (popular.isNotEmpty) {
      items.add(const _SectionHeader(icon: Icons.local_fire_department, label: 'Popular'));
      for (final e in popular) {
        items.add(_EventCard(
          event: e,
          isSaved: _savedEventIds.contains(e.id),
          onSaveToggled: () => _toggleSave(e),
        ));
      }
    }

    if (regular.isNotEmpty) {
      items.add(const _SectionHeader(icon: Icons.event, label: 'All Events'));
      for (final e in regular) {
        items.add(_EventCard(
          event: e,
          isSaved: _savedEventIds.contains(e.id),
          onSaveToggled: () => _toggleSave(e),
        ));
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Campus Events',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.orange,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: items),
    );
  }
}
```

### The Event Card — Hype Button and Bookmark

Each card is its own `StatefulWidget` because it manages local hype state
(the count and filled/unfilled fire icon) independently of the parent screen.

```dart
class _EventCardState extends State<_EventCard> {
  late bool _hasHyped; // has the current user hyped this event?
  late int  _hypeCount;
  // "late" = I promise to set this before it's read. Set in initState() below.

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Seed the initial state from the event snapshot.
    // If the user's UID is in hypedBy, they have already hyped it.
    _hasHyped  = uid != null && widget.event.hypedBy.contains(uid);
    _hypeCount = widget.event.hypeCount;
  }

  Future<void> _onHypeTapped() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final wasHyped = _hasHyped; // snapshot before we change anything

    // OPTIMISTIC UPDATE — flip the UI immediately without waiting for Firestore.
    // This makes the button feel instant. If Firestore fails we roll back.
    setState(() {
      _hasHyped   = !wasHyped;
      _hypeCount += wasHyped ? -1 : 1;
      // wasHyped = true means we are UN-hyping (subtract 1)
      // wasHyped = false means we are hyping (add 1)
    });

    try {
      if (wasHyped) {
        await _firestoreService.unhypeEvent(widget.event.id!, uid);
      } else {
        await _firestoreService.hypeEvent(widget.event.id!, uid);
      }
    } catch (_) {
      // Firestore failed (no internet, permissions error, etc.) — roll back.
      if (mounted) {
        setState(() {
          _hasHyped   = wasHyped;
          _hypeCount += wasHyped ? 1 : -1;
        });
      }
    }
  }
```

The hype button uses two animations stacked together:

```dart
// TweenAnimationBuilder creates an animated value that goes from `begin` to `end`.
// ValueKey(_hasHyped) restarts the animation every time _hasHyped flips — that
// is what causes the bounce on each tap.
TweenAnimationBuilder<double>(
  key: ValueKey(_hasHyped),
  tween: Tween(begin: 1.3, end: 1.0), // scale from 130% → 100%
  duration: const Duration(milliseconds: 350),
  curve: Curves.elasticOut, // overshoot then settle — feels springy
  builder: (context, scale, child) =>
      Transform.scale(scale: scale, child: child),

  child: Row(children: [
    // AnimatedSwitcher crossfades between two icons when its child changes.
    // ValueKey(_hasHyped) tells it "this is a different child now, animate."
    AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Icon(
        _hasHyped ? Icons.local_fire_department : Icons.local_fire_department_outlined,
        key: ValueKey(_hasHyped),
        color: _hasHyped ? Colors.orange : Colors.grey,
      ),
    ),
    // AnimatedSwitcher slides the count number up when it changes.
    AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5), // start slightly below
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Text('$_hypeCount', key: ValueKey(_hypeCount)),
    ),
  ]),
)
```

The card also shows a star rating badge and RSVP count when they exist:

```dart
// Star rating badge — only shown when at least one review exists
if (widget.event.reviewCount > 0)
  Row(children: [
    const Icon(Icons.star, color: Colors.amber, size: 14),
    Text(widget.event.averageRating.toStringAsFixed(1)),
    // .toStringAsFixed(1) = format to 1 decimal place: 4.166... → "4.2"
  ]),

// RSVP count badge
if (widget.event.rsvpCount > 0)
  Row(children: [
    const Icon(Icons.people, color: Colors.green, size: 14),
    Text('${widget.event.rsvpCount}'),
  ]),
```

---

## 8. Event Detail Screen

**What:** Full detail view for one event. Contains hype, RSVP, share, bookmark,
attendee list, star ratings, review list, and a "Get Directions" button.
**Where:** `lib/screens/event_detail_screen.dart`
**Why StatefulWidget:** Manages multiple pieces of async state (has the user hyped?
RSVP'd? saved? reviewed?) that all need to be loaded and updated independently.

### State Fields

```dart
class _EventDetailScreenState extends State<EventDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // Hype — seeded from the event snapshot, updated optimistically on tap
  late bool _hasHyped;
  late int  _hypeCount;

  // RSVP — starts false, loaded async in _loadRsvpStatus()
  bool _hasRsvpd = false;
  late int _rsvpCount;

  // Save/Favorites — starts false, loaded async in _loadSavedStatus()
  bool _hasSaved = false;

  // Rating — starts 0, loaded async in _loadReviewStatus()
  int    _myRating = 0;
  bool   _hasReviewed = false;
  bool   _submittingReview = false;
  late double _averageRating;
  late int    _reviewCount;
  final TextEditingController _commentController = TextEditingController();
  // TextEditingController links to a TextField widget — reads what the user typed.
  // Must be disposed in dispose() to free memory.

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    _hasHyped      = uid != null && widget.event.hypedBy.contains(uid);
    _hypeCount     = widget.event.hypeCount;
    _rsvpCount     = widget.event.rsvpCount;
    _averageRating = widget.event.averageRating;
    _reviewCount   = widget.event.reviewCount;

    // These three are async — we can't await in initState(), so we call
    // the methods and let them update state when they finish.
    _loadRsvpStatus();
    _loadSavedStatus();
    _loadReviewStatus();
  }

  @override
  void dispose() {
    _commentController.dispose(); // always dispose controllers
    super.dispose();
  }
```

### The Async Loaders

```dart
  Future<void> _loadRsvpStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.event.id == null) return;

    final hasRsvpd = await _firestoreService.checkUserRsvp(widget.event.id!, uid);
    // "mounted" is true while the widget is on screen.
    // Always check mounted before calling setState after an await — the user
    // might have gone back while we were waiting for Firestore.
    if (mounted) setState(() => _hasRsvpd = hasRsvpd);
  }

  Future<void> _loadSavedStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.event.id == null) return;

    final hasSaved = await _firestoreService.checkEventSaved(widget.event.id!, uid);
    if (mounted) setState(() => _hasSaved = hasSaved);
  }

  Future<void> _loadReviewStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.event.id == null) return;

    final review = await _firestoreService.getUserReview(widget.event.id!, uid);
    if (mounted && review != null) {
      setState(() {
        _hasReviewed = true;
        _myRating    = (review['rating']  as int?)    ?? 0;
        _commentController.text = (review['comment'] as String?) ?? '';
      });
    }
  }
```

### Share Button

```dart
  void _onShareTapped() {
    final date = DateFormat('MMM d, yyyy – h:mm a').format(widget.event.createdAt);
    // DateFormat from the intl package formats a DateTime into a readable string.
    // 'MMM d, yyyy' → "Apr 14, 2026"

    final text = '''
${widget.event.name}

${widget.event.description.isNotEmpty ? widget.event.description : 'No description.'}

📅 $date
📍 ${widget.event.latitude.toStringAsFixed(5)}, ${widget.event.longitude.toStringAsFixed(5)}

Shared via Campus Vibes'''.trim();
    // ''' ''' = multi-line string literal. $ inserts a variable's value.
    // .trim() removes leading/trailing whitespace from the entire block.

    Share.share(text, subject: widget.event.name);
    // Share.share() hands the text to the OS.
    // iOS opens the native share sheet (Messages, AirDrop, Mail, etc.)
    // Android opens the intent chooser.
  }
```

### RSVP Toggle

```dart
  Future<void> _onRsvpTapped() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final wasRsvpd = _hasRsvpd;
    setState(() {             // optimistic update
      _hasRsvpd   = !wasRsvpd;
      _rsvpCount += wasRsvpd ? -1 : 1;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (wasRsvpd) {
        await _firestoreService.unrsvpEvent(widget.event.id!, uid);
      } else {
        await _firestoreService.rsvpEvent(
          widget.event.id!, uid,
          displayName: user?.displayName,
          email:       user?.email,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {         // roll back on failure
          _hasRsvpd   = wasRsvpd;
          _rsvpCount += wasRsvpd ? 1 : -1;
        });
      }
    }
  }
```

### Rating Submit

```dart
  Future<void> _submitReview() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.event.id == null || _myRating == 0) return;

    // Capture ScaffoldMessenger BEFORE the first await.
    // After an await, "context" might no longer be valid (widget disposed).
    // Storing it in a variable before the await is the safe pattern.
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _submittingReview = true);

    try {
      await _firestoreService.submitReview(
        widget.event.id!, uid, _myRating, comment: _commentController.text);

      if (!mounted) return;
      setState(() { _hasReviewed = true; _submittingReview = false; });

      // Re-read the event doc to get the freshly computed average.
      final snap = await FirebaseFirestore.instance
          .collection('events').doc(widget.event.id).get();
      if (mounted && snap.exists) {
        final data = snap.data()!;
        setState(() {
          _averageRating = (data['averageRating'] ?? 0).toDouble();
          _reviewCount   = (data['reviewCount']   ?? 0) as int;
        });
      }

      messenger.showSnackBar(const SnackBar(content: Text('Review submitted!')));
    } catch (_) {
      if (mounted) setState(() => _submittingReview = false);
    }
  }
```

### Star Rating UI

```dart
// 5-star tap row — List.generate creates a list of 5 items.
// The builder receives the index (0–4). star = index + 1 = (1–5).
Row(
  children: List.generate(5, (i) {
    final star = i + 1;
    return GestureDetector(
      onTap: () => setState(() => _myRating = star),
      child: Icon(
        _myRating >= star ? Icons.star : Icons.star_border,
        // If _myRating is 3: stars 1,2,3 are filled; 4 and 5 are outlined.
        color: Colors.amber,
        size: 32,
      ),
    );
  }),
),

// Submit button — disabled (null onPressed) until a star is selected.
ElevatedButton(
  onPressed: (_myRating == 0 || _submittingReview) ? null : _submitReview,
  child: _submittingReview
      ? const CircularProgressIndicator(color: Colors.white)
      : Text(_hasReviewed ? 'Update Review' : 'Submit Review'),
),
```

### Reusable Animated Action Row (Hype + RSVP buttons)

Both the Hype and RSVP buttons on the detail screen share the same visual pattern —
a button that bounces on tap, plus an animated count beside it. We extract this into
one reusable widget to avoid duplicating the animation code.

```dart
// _AnimatedActionRow is used for both Hype and RSVP:
//   [animated button]   [sliding count text]
//
// Parameters let the caller configure the labels, icons, and colors.
// The widget doesn't need to know it's being used for hype vs RSVP.
class _AnimatedActionRow extends StatelessWidget {
  final bool isActive;
  final int count;
  final String activeLabel, inactiveLabel, countSuffix;
  final IconData activeIcon, inactiveIcon;
  final Color activeColor;
  final VoidCallback? onTap; // null = button is disabled

  // ...

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      // Bounce animation on toggle
      TweenAnimationBuilder<double>(
        key: ValueKey(isActive),
        tween: Tween(begin: 1.25, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(isActive ? activeIcon : inactiveIcon, key: ValueKey(isActive)),
          ),
          label: Text(isActive ? activeLabel : inactiveLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? activeColor.withValues(alpha: 0.1) : null,
            foregroundColor: isActive ? activeColor : null,
          ),
        ),
      ),
      const SizedBox(width: 12),
      // Count slides up when the number changes
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.5), end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Text('$count $countSuffix', key: ValueKey(count)),
      ),
    ]);
  }
}
```

---

## 9. Calendar Screen

**What:** A monthly calendar view of events. Days with events show an orange dot.
Tapping a day shows the events for that day in a list below the calendar.
Tapping an event opens its detail screen.
**Where:** `lib/screens/calendar_screen.dart`
**Package used:** `table_calendar`

### How Events Are Grouped by Day

```dart
// We group events into a Map<DateTime, List<Event>>.
// The key is a "normalized" DateTime — midnight of that day.
//
// WHY normalize to midnight?
// DateTime(2026, 4, 14, 9, 30) and DateTime(2026, 4, 14, 14, 0) are NOT equal.
// DateTime(2026, 4, 14) and DateTime(2026, 4, 14) ARE equal.
// Normalizing ensures all events on the same calendar day land in the same bucket.
Map<DateTime, List<Event>> _eventsByDay = {};

_eventsSubscription = _firestoreService.getEventsStream().listen((events) {
  final Map<DateTime, List<Event>> grouped = {};
  for (final event in events) {
    final day = DateTime(
      event.createdAt.year,
      event.createdAt.month,
      event.createdAt.day, // time-of-day is stripped — only year/month/day kept
    );
    // putIfAbsent: if no list exists for this day yet, create one first.
    grouped.putIfAbsent(day, () => []).add(event);
  }
  setState(() => _eventsByDay = grouped);
});

// _getEventsForDay is called by table_calendar for every visible day.
// Returning a non-empty list causes a dot indicator to appear under that day.
List<Event> _getEventsForDay(DateTime day) {
  final key = DateTime(day.year, day.month, day.day); // normalize lookup key too
  return _eventsByDay[key] ?? []; // ?? [] = empty list if no events that day
}
```

### The TableCalendar Widget

```dart
TableCalendar<Event>(
  firstDay: DateTime.utc(2020, 1, 1),
  lastDay:  DateTime.utc(2030, 12, 31),
  focusedDay: _focusedDay,
  // focusedDay = which month the calendar is currently showing

  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
  // isSameDay() handles timezone edge cases — safer than == for dates

  eventLoader: _getEventsForDay,
  // table_calendar calls this for every visible day.
  // If the list is non-empty, it draws a dot under that day.

  onDaySelected: (selectedDay, focusedDay) {
    setState(() {
      _selectedDay = selectedDay; // update which day is highlighted
      _focusedDay  = focusedDay;  // keep the month view in sync
    });
  },

  calendarStyle: CalendarStyle(
    markerDecoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
    // markerDecoration = the dot style under days that have events

    selectedDecoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
    // selectedDecoration = the circle around the tapped/selected day

    todayDecoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.35), // lighter so it doesn't clash
      shape: BoxShape.circle,
    ),
  ),

  headerStyle: const HeaderStyle(
    formatButtonVisible: false, // hide the "Month / 2 weeks" toggle button
    titleCentered: true,
  ),
),
```

---

## 10. Live Navigation

**What:** A full walking navigation screen. Shows a Mapbox map with a blue route line
from the user's GPS position to the event. The line shrinks as the user walks.
Automatically reroutes if the user goes off-path. Shows an arrival overlay when they get close.
Also lets the user swap the GPS puck icon between two custom images.
**Where:** `lib/screens/live_navigation.dart`
**Supporting files:**
- `lib/logic/navigation_access_evaluator.dart` — GPS permission logic
- `lib/config/app_config.dart` — Mapbox token + dev flags
- `lib/services/app_logger.dart` — debug logging helper

### NavigationPhase — The State Machine

```dart
// An enum is a fixed set of named values.
// The screen is always in exactly ONE phase at a time.
// This drives what gets shown to the user.
enum NavigationPhase {
  initializing, // map loaded, setting up GPS and permission
  loadingRoute, // waiting for Directions API response
  tracking,     // route is drawn, GPS stream is running
  rerouting,    // user went off-route, recalculating
  arrived,      // within 12 m of destination
  error,        // something failed
}
```

### Key State Fields

```dart
MapboxMap? _mapboxMap;
// Null until the Mapbox SDK calls _onMapCreated().

StreamSubscription<geo.Position>? _positionStream;
// The live GPS stream subscription. Cancel in dispose() or GPS runs forever.

// Source/layer IDs — must be unique strings in the Mapbox style.
static const _routeSourceId = 'live-route-source';
static const _routeLayerId  = 'live-route-layer';

// Navigation thresholds
static const double _minMovementMeters      = 2.0;  // ignore GPS wobble smaller than this
static const double _offRouteThresholdMeters = 40.0; // reroute if farther than this from route
static const double _arrivalThresholdMeters  = 12.0; // "arrived" when this close to destination
static const Duration _rerouteCooldown = Duration(seconds: 20); // wait between reroutes

List<List<double>> _fullRouteCoords = [];
// The walking route as a list of [longitude, latitude] pairs.
// IMPORTANT: Mapbox uses [lng, lat] order — opposite of the common [lat, lng].
// We trim from the front of this list as the user walks forward.

int _lastClosestIndex = 0;
// Index into _fullRouteCoords of the route point nearest to the user.
// Used to find the "trim point" — everything before this is behind the user.

String _currentIcon = "assets/pic1a.png";
// Which custom puck icon is currently displayed.
// Toggled by the FAB button.
```

### The Navigation Flow

```dart
// Called once when the map style loads. This kicks off the full sequence.
Future<void> _startNavigationFlow() async {
  // 1. Check GPS permission
  final canUseLiveLocation = await _resolveLocationAccess();

  // 2. Show/hide the GPS puck dot
  await _configureLocationPuck(canUseLiveLocation);

  if (!canUseLiveLocation) return; // show error, stop here

  // 3. Fetch walking route from Mapbox Directions API
  final routeLoaded = await _recalculateRoute(useDeviceLocation: true);
  if (!routeLoaded) return;

  // 4. Start continuous GPS stream
  _startPositionTracking();

  // 5. Switch camera to follow the user's puck
  _transitionToFollowPuck();
}
```

### How the Route Gets Drawn — Mapbox Sources and Layers

```dart
// In Mapbox, drawing anything on the map takes two steps:
//   Source = the data container (holds GeoJSON — geographic shape data as JSON)
//   Layer  = the visual style rule (how to draw the source: blue line, 5px wide)

// STEP 1: Add an empty source (no route yet)
await _mapboxMap!.style.addSource(
  GeoJsonSource(
    id: _routeSourceId,
    data: '{"type":"FeatureCollection","features":[]}',
    // FeatureCollection with zero features = nothing drawn yet
  ),
);

// STEP 2: Add a line layer that reads from that source
await _mapboxMap!.style.addLayer(
  LineLayer(
    id: _routeLayerId,
    sourceId: _routeSourceId, // connects this layer to the source above
    lineColor: Colors.blue.toARGB32(), // toARGB32() converts Flutter Color → int
    lineWidth: 5.0,
  ),
);

// LATER: update just the source data — the layer redraws automatically.
await _mapboxMap!.style.setStyleSourceProperty(
  _routeSourceId,
  'data',
  routeGeoJson, // the JSON string with the route coordinates
);
```

### Fetching the Route — Mapbox Directions API

```dart
// The Directions API returns a GeoJSON LineString — a list of [lng, lat] points
// that trace the walking path.
//
// URL format:
// /directions/v5/mapbox/walking/{startLng},{startLat};{destLng},{destLat}
// ?geometries=geojson  ← return route as GeoJSON
// &access_token=...    ← your Mapbox API key

final uri = Uri.parse(
  'https://api.mapbox.com/directions/v5/mapbox/walking/'
  '$startLng,$startLat;${widget.destLng},${widget.destLat}'
  '?geometries=geojson&access_token=${AppConfig.mapboxAccessToken}',
);

// Retry up to 3 times with exponential backoff (700ms → 1400ms → 2800ms).
// Backoff = wait longer between each retry so we don't spam the API.
for (int attempt = 1; attempt <= 3; attempt++) {
  final response = await http.get(uri).timeout(Duration(seconds: 10));
  if (response.statusCode == 200) {
    return _extractRouteCoordinates(response.body); // success
  }
  await Future.delayed(backoff);
  backoff = Duration(milliseconds: backoff.inMilliseconds * 2);
}
```

### Route Trimming — Making the Line Shrink

```dart
// Called on every GPS update while tracking.
void _updateRouteProgress(geo.Position position) {

  // Find which route point is nearest to the user right now.
  // Returns both the index and the distance in meters.
  final (closestIndex, minDistance) = _findClosestRoutePoint(position);

  // Check arrival
  final distToDestination = geo.Geolocator.distanceBetween(
    position.latitude, position.longitude, widget.destLat, widget.destLng);

  if (distToDestination <= 12.0) {
    // Show arrival overlay and stop tracking
    setState(() => _phase = NavigationPhase.arrived);
    return;
  }

  // Check off-route
  if (minDistance > 40.0) {
    unawaited(_rerouteFromPosition(position, minDistance));
    // unawaited() = fire and forget. We can't await in a non-async function.
    return;
  }

  // Trim the route — discard everything behind the user.
  // sublist(closestIndex) creates a NEW list starting at closestIndex.
  // Everything before that index is behind the user — we drop it.
  // This is what makes the blue line shrink as the user walks forward.
  final remainingRoute = _fullRouteCoords.sublist(closestIndex);
  unawaited(_updateMapWithCoords(remainingRoute));
}
```

### Custom GPS Puck Icons

The GPS puck is the dot that appears on the map at the user's location.
This feature replaces the default blue circle with a custom image from the app's assets,
and adds a button to toggle between two different icons.

```dart
// FloatingActionButton in the Scaffold — appears bottom-right over the map.
floatingActionButton: FloatingActionButton(
  onPressed: _chooseIcon,
  child: const Icon(Icons.image), // picture icon = "change the puck icon"
),
```

```dart
// _chooseIcon() toggles the puck icon and applies it to the live map.
void _chooseIcon() async {
  if (_mapboxMap == null) return;

  // Ternary expression: condition ? value_if_true : value_if_false
  // Flip between the two icon asset paths.
  setState(() {
    _currentIcon = _currentIcon == "assets/pic1a.png"
        ? "assets/pic1b.png"
        : "assets/pic1a.png";
  });

  // rootBundle.load() reads a file from the assets/ folder.
  // Returns ByteData — the raw binary content of the image file.
  // await pauses here until the file is fully read.
  final ByteData bytes = await rootBundle.load(_currentIcon);

  // Convert ByteData → Uint8List (unsigned 8-bit integer list = raw bytes).
  // Mapbox's LocationPuck2D.topImage requires Uint8List — not a file path,
  // not an AssetImage, but the actual raw bytes of the image.
  final Uint8List imageData = bytes.buffer.asUint8List();

  // Apply the new icon to the live location puck on the map.
  _mapboxMap!.location.updateSettings(
    LocationComponentSettings(
      enabled:            true, // keep the puck visible
      puckBearingEnabled: true, // keep rotating with device heading
      locationPuck: LocationPuck(
        locationPuck2D: LocationPuck2D(
          topImage: imageData,
          // topImage = the main icon drawn at the user's position.
          // Mapbox also supports shadowImage (shadow under the puck)
          // and bearingImage (directional arrow) for a layered puck look.
        ),
      ),
    ),
  );
}
```

### Permission Checking — NavigationAccessEvaluator

GPS permission is checked in a separate file (`lib/logic/navigation_access_evaluator.dart`)
rather than inside `live_navigation.dart`. This separation makes the logic independently
testable — you can verify every permission scenario without needing a real device or map.

```dart
// Two things must BOTH be true before navigation can work:
//   1. Location Services ON system-wide (the GPS toggle in phone Settings)
//   2. This app has been granted location permission by the user

final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
geo.LocationPermission permission = await geo.Geolocator.checkPermission();

// If denied but not permanently, show the system dialog to ask the user.
if (serviceEnabled && permission == geo.LocationPermission.denied) {
  permission = await geo.Geolocator.requestPermission();
}

// NavigationAccessEvaluator reads the results and returns a decision:
//   canUseLiveLocation = true → everything is fine, start navigation
//   canUseLiveLocation = false → show message + action buttons (Retry, Settings)
final decision = NavigationAccessEvaluator.evaluate(
  serviceEnabled: serviceEnabled,
  permission: permission,
);
```

### AppConfig — Mapbox Token

```dart
// lib/config/app_config.dart
//
// String.fromEnvironment reads a value passed via --dart-define at compile time.
// If no value is passed, defaultValue is used.
// This keeps the token out of version control in production.
//
// Usage: flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here

class AppConfig {
  AppConfig._(); // private constructor — never instantiated, only static access

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'pk.eyJ1...', // hardcoded fallback for development
  );
}
```

---

## Key Patterns Quick Reference

| Pattern | What it does | Where used |
|---|---|---|
| Optimistic update | Flip UI immediately, write to Firestore, roll back on failure | Hype, RSVP, Save |
| Firestore transaction | Multiple reads/writes that succeed or fail together — no partial updates | RSVP, Rating |
| `FieldValue.arrayUnion/Remove` | Add/remove from array without duplicates, server-side safe | Hype |
| `FieldValue.increment` | Atomic counter — no race conditions even with concurrent users | Hype, RSVP, Rating |
| `StreamSubscription` + `dispose()` | Listen to live data; cancel when screen closes to prevent leaks | Events screen, Calendar, Map |
| `Set<String>` for ID lookup | O(1) `.contains()` — instant regardless of how many items | Saved event IDs |
| `late` keyword | "I promise to set this before it's read" — set in `initState()` | Hype/RSVP counts |
| `mounted` check after `await` | Prevents `setState()` on a widget that was removed while waiting | All async state methods |
| Capture `ScaffoldMessenger` before `await` | Prevents using an invalid `context` after an async gap | Rating submit |
| Normalize `DateTime` to midnight | Reliable map key for grouping events by calendar day | Calendar screen |
| Client-side sort vs Firestore `orderBy` | Avoids Firestore excluding old documents that lack the sort field | Hype sorting |
| `unawaited()` | Fire-and-forget an async call from a non-async function | Route trimming, rerouting |
