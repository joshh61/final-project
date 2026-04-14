# Campus Vibes — Feature Implementation Guide

This file walks through every feature added to the Campus Vibes app in implementation order.
Each section explains the concept first, then shows the exact code needed to build it from scratch.
The comments follow the same teaching style as `campus_vibes_learn` — explaining the **why**,
not just the **what**.

---

## Table of Contents

1. [Setup — Dependencies](#1-setup--dependencies)
2. [Live Navigation — What Changed and Why](#2-live-navigation--what-changed-and-why)
3. [Hype System](#3-hype-system-25)
4. [RSVPs](#4-rsvps-10)
5. [Share Events](#5-share-events-11)
6. [Save / Favorites](#6-save--favorites-7)
7. [Calendar View](#7-calendar-view-5)
8. [Rating System](#8-rating-system-23)

---

## 1. Setup — Dependencies

Open `pubspec.yaml` and add these two packages under `dependencies`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # --- existing packages ---
  firebase_core: ^4.4.0
  cloud_firestore: ^6.1.2
  firebase_auth: ^6.1.4
  geolocator: ^10.1.0
  intl: ^0.20.2
  mapbox_maps_flutter: 2.18.0
  http: ^1.1.0

  # --- new packages added for features ---

  # share_plus — opens the native share sheet (iOS/Android) so users can
  # send event details via iMessage, WhatsApp, email, etc.
  share_plus: ^10.1.4

  # table_calendar — renders a full monthly calendar widget with dot
  # indicators on days that have events. Much easier than building one manually.
  table_calendar: ^3.1.2
```

Then run:

```bash
flutter pub get
```

---

## 2. Live Navigation — What Changed and Why

### Background

The project originally had a large "one-shot" navigation file (~1,248 lines) that was built
during an earlier development phase. It worked, but it contained several features that were
either not needed for the final app or made the code harder to follow as a learning resource:

- A **debug panel** (a collapsible overlay showing raw GPS coordinates, HTTP status codes,
  and internal timing values). Useful during development, but confusing for users and
  not part of the final product.
- A **"recenter" floating action button** that re-locked the camera to the user's puck
  after the user manually panned the map. Removed to simplify the UI — the camera
  always follows the puck once tracking starts.
- **Dark/light theme sync** (`didChangeDependencies` + `_applyThemeToMap`). The map
  style was being updated whenever the phone switched between dark and light mode.
  Removed because Campus Vibes uses a fixed orange theme and doesn't support dark mode.
- **Scroll detection** (`_onUserScroll`) that tracked when the user panned the map
  so the recenter button knew when to appear. Removed along with the recenter button.
- Several **internal flags** (`_isFollowingPuck`, `_isTransitioningCamera`,
  `_lastAppliedBrightness`, `_lastHttpStatus`, `_startMode`, `_lastRouteUpdatedAt`)
  that supported the removed features above.

The stripped-down version (~750 lines, now fully commented in `lib/screens/live_navigation.dart`)
keeps everything that actually matters for a walking navigation experience:

- GPS permission checking
- Mapbox Directions API fetch with retry + exponential backoff
- Real-time route trimming as the user walks
- Off-route detection and automatic rerouting
- Arrival detection

---

### What Was Removed — Line by Line

Below is a summary of every removal so you could reconstruct the original if needed,
or understand exactly what the current file is *not* doing.

#### 1. `import 'package:flutter/foundation.dart'`
```dart
// REMOVED — was only needed for kDebugMode used in the debug panel.
// kDebugMode is true when running a debug build, false in release.
import 'package:flutter/foundation.dart';
```

#### 2. Debug panel state variables
```dart
// REMOVED — these fields tracked whether the debug overlay was visible
// and what values to display inside it.
bool _showDebugPanel = false;
String _lastHttpStatus = '';       // last Directions API HTTP status code
String _startMode = '';            // 'device' or 'fallback'
DateTime? _lastRouteUpdatedAt;     // timestamp of last successful route fetch
```

#### 3. Dark/light theme sync
```dart
// REMOVED — this lifecycle method fired every time the system brightness changed
// (phone switches to dark mode). It called _applyThemeToMap() to reload the map style.
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final brightness = Theme.of(context).brightness;
  if (_mapboxMap != null && brightness != _lastAppliedBrightness) {
    _applyThemeToMap(brightness);
    _lastAppliedBrightness = brightness;
  }
}

// REMOVED — reloaded the Mapbox style URI based on dark/light mode.
Future<void> _applyThemeToMap(Brightness brightness) async {
  final styleUri = brightness == Brightness.dark
      ? MapboxStyles.DARK
      : MapboxStyles.STANDARD;
  await _mapboxMap?.loadStyleURI(styleUri);
}

// REMOVED — stored the last brightness so we only reload when it actually changes.
Brightness? _lastAppliedBrightness;
```

#### 4. Camera follow / scroll detection state
```dart
// REMOVED — tracked whether the camera was locked to the puck.
// When false, the recenter FAB appeared.
bool _isFollowingPuck = true;

// REMOVED — prevented scroll detection from firing while an animated camera
// transition was already in progress.
bool _isTransitioningCamera = false;

// REMOVED — the GestureRecognizer that detected when the user manually panned
// the map, which would un-lock the camera and show the recenter button.
void _onUserScroll(MapContentGestureContext context) {
  if (_isTransitioningCamera) return;
  if (_isFollowingPuck) {
    setState(() => _isFollowingPuck = false);
  }
}
```

#### 5. Recenter floating action button
```dart
// REMOVED — appeared at the bottom-right when the user panned away from their puck.
// Tapping it re-locked the camera to follow the user again.
Widget _buildRecenterFab() {
  return Positioned(
    bottom: 24,
    right: 16,
    child: FloatingActionButton.small(
      onPressed: _recenterOnPuck,
      backgroundColor: Colors.white,
      child: const Icon(Icons.my_location, color: Colors.blue),
    ),
  );
}

Future<void> _recenterOnPuck() async {
  setState(() {
    _isFollowingPuck = true;
    _isTransitioningCamera = true;
  });
  _transitionToFollowPuck();
  await Future.delayed(const Duration(milliseconds: 600));
  if (mounted) setState(() => _isTransitioningCamera = false);
}
```

#### 6. Debug panel UI
```dart
// REMOVED — a collapsible overlay at the bottom of the map showing internal
// state values. Only shown in debug builds (kDebugMode).

// Toggle button in AppBar:
if (kDebugMode)
  IconButton(
    icon: Icon(_showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined),
    onPressed: () => setState(() => _showDebugPanel = !_showDebugPanel),
  ),

// The panel itself:
Widget _buildDebugPanel() {
  return Positioned(
    left: 12,
    right: 12,
    bottom: 80,
    child: Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phase: $_phase', style: const TextStyle(color: Colors.white, fontSize: 11)),
            Text('Route pts: ${_fullRouteCoords.length}', ...),
            Text('HTTP: $_lastHttpStatus', ...),
            Text('Start: $_startMode', ...),
            Text('Closest idx: $_lastClosestIndex', ...),
            if (_lastRouteUpdatedAt != null)
              Text('Last route: ${_lastRouteUpdatedAt!.toIso8601String()}', ...),
          ],
        ),
      ),
    ),
  );
}
```

---

### What Was Added

Only one thing was added compared to the one-shot version:

#### The `eventName` parameter
```dart
// ADDED — the one-shot version had no eventName parameter.
// The AppBar just showed a generic title like "Navigating".
// We added eventName so the AppBar and arrival card both show the actual event name.

const LiveNavigationScreen({
  super.key,
  required this.destLat,
  required this.destLng,
  required this.eventName,  // ← new
});
```

And the corresponding usage in EventDetailScreen:
```dart
// BEFORE (one-shot version — missing eventName, caused a compile error):
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => LiveNavigationScreen(
      destLat: widget.event.latitude,
      destLng: widget.event.longitude,
      // eventName was missing — compile error
    ),
  ),
);

// AFTER (fixed):
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => LiveNavigationScreen(
      destLat: widget.event.latitude,
      destLng: widget.event.longitude,
      eventName: widget.event.name,  // ← added
    ),
  ),
);
```

---

### The Supporting Files (unchanged)

Two files support the navigation screen and were not modified:

**`lib/logic/navigation_access_evaluator.dart`**
Handles all GPS permission logic. Takes the current `serviceEnabled` bool and
`LocationPermission` enum value, and returns a `NavigationAccessDecision` object
describing whether navigation is allowed, what error message to show, and which
action buttons (Retry, App Settings, Location Settings) to display.

Keeping this logic in its own file makes it independently testable — you can
verify every permission scenario without needing the map or GPS hardware.

**`lib/config/app_config.dart`**
Reads the Mapbox access token from `--dart-define` at compile time using
`String.fromEnvironment()`. If no value is passed, the hardcoded default token
is used. Also exposes `enableDevTools` and `enableVerboseLogs` flags.

```bash
# How to pass the token at run time (optional — default is already set):
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here
```

---

## 3. Hype System (#25)

### Concept

A "Hype" is like a campus-specific version of a like or upvote.
Each user can hype an event once — tapping again un-hypes it (a toggle).

**Firestore design:**
- `hypeCount` (int) — cached total on the event document. Fast to display.
- `hypedBy` (array of UIDs) — tracks who has already hyped so we prevent duplicates.

We use `FieldValue.arrayUnion` / `FieldValue.arrayRemove` (atomic Firestore operations)
so two users hyping at the same instant don't accidentally overwrite each other.

The UI uses an **optimistic update** pattern:
flip the button immediately → write to Firestore → roll back on failure.
This makes the app feel instant even on slow connections.

---

### Step 1 — Update the Event Model (`lib/models/event.dart`)

Add three new fields. Existing documents in Firestore that don't have these fields
will safely default to `0` / `[]` because of the `??` fallback in `fromFirestore`.

```dart
class Event {
  final String? id;
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  // --- NEW HYPE FIELDS ---

  // int = whole number. How many unique users have hyped this event.
  // We store this separately so we can display it without reading hypedBy.
  final int hypeCount;

  // List<String> = a list of text values. Stores every UID that has hyped.
  // We check .contains(uid) before allowing another hype — no double-hyping.
  // const [] = an immutable empty list used as the default value.
  final List<String> hypedBy;

  Event({
    this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    DateTime? createdAt,
    this.hypeCount = 0,       // new events start at 0
    this.hypedBy = const [],  // new events have nobody in the list
  }) : createdAt = createdAt ?? DateTime.now();

  // toMap() — called when SAVING an event to Firestore.
  // Add the new fields here so they get written to the database.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'hypeCount': hypeCount,  // <-- new
      'hypedBy': hypedBy,      // <-- new
    };
  }

  // fromFirestore() — called when READING an event from Firestore.
  // The ?? gives a safe default if the field doesn't exist on old documents.
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
      hypeCount: (data['hypeCount'] ?? 0) as int,           // <-- new
      hypedBy: List<String>.from(data['hypedBy'] ?? []),    // <-- new
    );
  }
}
```

---

### Step 2 — Firestore Service Methods (`lib/services/firestore_service.dart`)

```dart
// hypeEvent — adds the user's UID to hypedBy and increments hypeCount by 1.
// Both happen in a single Firestore write, so they're always in sync.
Future<void> hypeEvent(String eventId, String uid) async {
  await _eventsCollection.doc(eventId).update({
    // arrayUnion adds uid ONLY if it's not already in the list.
    // This is the Firestore-safe way to prevent duplicate entries.
    'hypedBy': FieldValue.arrayUnion([uid]),

    // increment is atomic on the server — even if two users hype at the
    // exact same millisecond, neither write overwrites the other.
    'hypeCount': FieldValue.increment(1),
  });
}

// unhypeEvent — removes the user's UID and decrements hypeCount by 1.
// Called when the user taps the hype button a second time to toggle it off.
Future<void> unhypeEvent(String eventId, String uid) async {
  await _eventsCollection.doc(eventId).update({
    // arrayRemove removes uid from the list. If uid isn't there, it's a no-op.
    'hypedBy': FieldValue.arrayRemove([uid]),
    'hypeCount': FieldValue.increment(-1),
  });
}
```

---

### Step 3 — Event Card Hype Button (inside `_EventCardState`)

The card uses local state so the button responds instantly without waiting for Firestore.

```dart
class _EventCardState extends State<_EventCard> {
  final FirestoreService _firestoreService = FirestoreService();

  // --- LOCAL HYPE STATE ---
  // late = "I'll set this in initState before it's ever read."
  // We store these locally so we can flip them instantly on tap.
  // Without local state, the button would feel laggy — it would wait
  // for Firestore to confirm before updating the icon.
  late bool _hasHyped;
  late int _hypeCount;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // widget.event is the Event object passed into this card.
    // We seed the initial state from the Firestore snapshot.
    // If the current user's UID is in hypedBy, they've already hyped it.
    _hasHyped = uid != null && widget.event.hypedBy.contains(uid);
    _hypeCount = widget.event.hypeCount;
  }

  // _onHypeTapped is async because it eventually talks to Firestore.
  // But the UI updates BEFORE the async work starts — that's the key.
  Future<void> _onHypeTapped() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // user must be logged in

    final wasHyped = _hasHyped; // snapshot of the state before we change it

    // OPTIMISTIC UPDATE — flip the UI immediately, don't wait for Firebase.
    setState(() {
      _hasHyped = !wasHyped;
      _hypeCount += wasHyped ? -1 : 1; // wasHyped=true means we're un-hyping
    });

    try {
      // Now do the actual Firestore write in the background.
      if (wasHyped) {
        await _firestoreService.unhypeEvent(widget.event.id!, uid);
      } else {
        await _firestoreService.hypeEvent(widget.event.id!, uid);
      }
    } catch (_) {
      // If Firestore fails (no internet, permissions, etc.), roll back
      // the UI to the original state. The user sees the correction.
      if (mounted) {
        setState(() {
          _hasHyped = wasHyped;
          _hypeCount += wasHyped ? 1 : -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Animated hype button — scale bounce + icon crossfade + count slide-up.
      // ValueKey(_hasHyped) forces the animation to restart every time
      // the hype state changes — that's what triggers the bounce.
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_hasHyped),
        tween: Tween(begin: 1.3, end: 1.0), // starts at 130% size, shrinks to 100%
        duration: const Duration(milliseconds: 350),
        curve: Curves.elasticOut, // overshoot then settle — feels springy
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AnimatedSwitcher crossfades between the two icons.
            // ValueKey(_hasHyped) tells it "this is a different widget now, animate."
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _hasHyped
                    ? Icons.local_fire_department          // filled = hyped
                    : Icons.local_fire_department_outlined, // outline = not hyped
                key: ValueKey(_hasHyped),
                color: _hasHyped ? Colors.orange : Colors.grey,
                size: 18,
              ),
            ),
            const SizedBox(width: 3),
            // AnimatedSwitcher slides the count number up when it changes.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => SlideTransition(
                // Slide from below (Offset(0, 0.5)) to its natural position (Offset.zero).
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Text(
                '$_hypeCount',
                key: ValueKey(_hypeCount), // change triggers the slide animation
                style: TextStyle(
                  fontSize: 12,
                  color: _hasHyped ? Colors.orange : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

### Step 4 — Sorting Events by Hype (in `_EventsScreenState`)

We sort client-side instead of using Firestore `orderBy('hypeCount')` because
`orderBy` on a field **excludes any document that doesn't have that field**.
Old events without `hypeCount` would silently disappear from the list.

```dart
_eventsSubscription = _firestoreService.getEventsStream().listen((events) {
  // Sort descending — most hyped event at index 0.
  // compareTo returns negative/zero/positive, so reversing gives descending order.
  events.sort((a, b) => b.hypeCount.compareTo(a.hypeCount));

  setState(() {
    _allEvents = events;
    _loading = false;
  });
});
```

---

### Step 5 — "Popular" Section Header Logic

Split the sorted list into sections based on hype count:

```dart
// Events with at least this many hypes get their own "Popular" section.
const int _popularThreshold = 1;

final popular = _allEvents.where((e) => e.hypeCount >= _popularThreshold).toList();
final regular = _allEvents.where((e) => e.hypeCount < _popularThreshold).toList();

// Build a flat list of headers + cards for a single scrollable ListView.
final List<Widget> items = [];

if (popular.isNotEmpty) {
  items.add(const _SectionHeader(icon: Icons.local_fire_department, label: 'Popular'));
  for (final e in popular) {
    items.add(_EventCard(event: e));
  }
}

if (regular.isNotEmpty) {
  items.add(const _SectionHeader(icon: Icons.event, label: 'All Events'));
  for (final e in regular) {
    items.add(_EventCard(event: e));
  }
}
```

---

## 4. RSVPs (#10)

### Concept

RSVPs answer the question "who is coming?" Each user gets one RSVP per event.
We use a **Firestore subcollection** instead of an array field because:

- Each RSVP document can store extra data (display name, email, timestamp)
- Subcollections scale to thousands of attendees without hitting Firestore's 1 MB document limit
- We can query and display the attendee list independently

**Firestore structure:**
```
events/
  {eventId}/
    rsvps/
      {userId}    ← one document per attendee
        rsvpdAt: Timestamp
        displayName: "Matt Berry"
        email: "matt@utrgv.edu"
```

We use a **Firestore transaction** to update both the RSVP subcollection document
and the `rsvpCount` counter on the event document at the same time.
Transactions either succeed completely or fail completely — the count never drifts.

---

### Step 1 — Add `rsvpCount` to the Event Model

```dart
class Event {
  // ... existing fields ...

  // How many users have RSVP'd. Stored on the event document so we can
  // display it on cards without querying the rsvps subcollection every time.
  final int rsvpCount;

  Event({
    // ... existing params ...
    this.rsvpCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      // ... existing fields ...
      'rsvpCount': rsvpCount,
    };
  }

  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      // ... existing fields ...
      rsvpCount: (data['rsvpCount'] ?? 0) as int,
    );
  }
}
```

---

### Step 2 — Firestore Service Methods

```dart
// rsvpEvent — creates an RSVP document and increments rsvpCount atomically.
// displayName and email are optional — they're stored so the attendee list
// can show real names without looking up users in a separate collection.
Future<void> rsvpEvent(
  String eventId,
  String uid, {
  String? displayName,
  String? email,
}) async {
  final eventRef = _eventsCollection.doc(eventId);

  // A subcollection reference — Firestore creates the 'rsvps' subcollection
  // automatically on the first write. No setup needed.
  final rsvpRef = eventRef.collection('rsvps').doc(uid);

  // runTransaction groups the reads and writes so they succeed or fail together.
  // This prevents the count and the subcollection from getting out of sync.
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final rsvpDoc = await transaction.get(rsvpRef); // must read before writing
    if (rsvpDoc.exists) return; // already RSVP'd — nothing to do

    transaction.set(rsvpRef, {
      'rsvpdAt': FieldValue.serverTimestamp(), // server time, not device time
      'displayName': displayName,
      'email': email,
    });
    transaction.update(eventRef, {'rsvpCount': FieldValue.increment(1)});
  });
}

// unrsvpEvent — deletes the RSVP document and decrements rsvpCount.
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

// checkUserRsvp — one-time read. Returns true if the user has RSVP'd.
// Used to seed the button state when the detail screen opens.
Future<bool> checkUserRsvp(String eventId, String uid) async {
  final doc = await _eventsCollection
      .doc(eventId)
      .collection('rsvps')
      .doc(uid)
      .get();
  return doc.exists;
}

// getRsvpsStream — live stream of all attendee documents for an event.
// The UI rebuilds automatically whenever someone RSVPs or un-RSVPs.
Stream<QuerySnapshot> getRsvpsStream(String eventId) {
  return _eventsCollection
      .doc(eventId)
      .collection('rsvps')
      .orderBy('rsvpdAt') // show earliest RSVPs first
      .snapshots();
}
```

---

### Step 3 — RSVP Button + Attendee List (in `EventDetailScreen`)

Add this state to `_EventDetailScreenState`:

```dart
bool _hasRsvpd = false;   // starts false; loaded async in initState
late int _rsvpCount;      // seeded from widget.event.rsvpCount

@override
void initState() {
  super.initState();
  _rsvpCount = widget.event.rsvpCount;
  _loadRsvpStatus(); // kicks off the async check
}

// _loadRsvpStatus reads the subcollection to check if this user has RSVP'd.
// We can't know this from the event snapshot alone because RSVP status
// is stored per-user in a subcollection, not on the event document.
Future<void> _loadRsvpStatus() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || widget.event.id == null) return;

  final hasRsvpd = await _firestoreService.checkUserRsvp(widget.event.id!, uid);
  if (mounted) setState(() => _hasRsvpd = hasRsvpd);
  // mounted check prevents calling setState on a widget that was already
  // removed from the tree while we were waiting for Firestore.
}

Future<void> _onRsvpTapped() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final wasRsvpd = _hasRsvpd;
  setState(() {           // optimistic update
    _hasRsvpd = !wasRsvpd;
    _rsvpCount += wasRsvpd ? -1 : 1;
  });

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (wasRsvpd) {
      await _firestoreService.unrsvpEvent(widget.event.id!, uid);
    } else {
      await _firestoreService.rsvpEvent(
        widget.event.id!,
        uid,
        displayName: user?.displayName,
        email: user?.email,
      );
    }
  } catch (_) {
    if (mounted) {
      setState(() {         // roll back on failure
        _hasRsvpd = wasRsvpd;
        _rsvpCount += wasRsvpd ? 1 : -1;
      });
    }
  }
}
```

Attendee list widget (add anywhere in the build column):

```dart
// _AttendeeList uses ExpansionTile so it starts collapsed.
// StreamBuilder keeps the list live — new RSVPs appear without refreshing.
class _AttendeeList extends StatelessWidget {
  final String eventId;
  final int rsvpCount;
  final FirestoreService firestoreService;

  const _AttendeeList({
    required this.eventId,
    required this.rsvpCount,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.people, color: Colors.green),
        title: Text(
          rsvpCount == 0
              ? 'No attendees yet'
              : '$rsvpCount ${rsvpCount == 1 ? 'person' : 'people'} going',
        ),
        // Hide the expand arrow when there's nothing to expand.
        trailing: rsvpCount == 0 ? const SizedBox.shrink() : null,
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getRsvpsStream(eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator(color: Colors.green);
              }

              final rsvps = snapshot.data?.docs ?? [];

              // shrinkWrap + NeverScrollableScrollPhysics lets this ListView
              // live inside a parent ScrollView without scroll conflicts.
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rsvps.length,
                itemBuilder: (context, index) {
                  final data = rsvps[index].data() as Map<String, dynamic>;
                  // Show displayName → email → 'Anonymous' in that priority order.
                  final name = (data['displayName'] as String?)?.isNotEmpty == true
                      ? data['displayName'] as String
                      : (data['email'] as String?) ?? 'Anonymous';

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.shade100,
                      // First letter of the name as a simple avatar.
                      child: Text(name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 12, color: Colors.green)),
                    ),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
```

---

## 5. Share Events (#11)

### Concept

Tapping Share opens the native OS share sheet — no custom UI needed.
The `share_plus` package does all the heavy lifting.
We just build a plain-text string with the event details and hand it off.

---

### Step 1 — Import

```dart
import 'package:share_plus/share_plus.dart';
```

---

### Step 2 — Share Handler (in `_EventDetailScreenState`)

```dart
void _onShareTapped() {
  // DateFormat comes from the intl package — formats DateTime into readable text.
  // 'MMM d, yyyy – h:mm a' produces something like "Apr 14, 2026 – 7:30 PM"
  final date = DateFormat('MMM d, yyyy – h:mm a').format(widget.event.createdAt);

  // Multi-line string using triple quotes. $ inserts variables into the text.
  // .trim() removes any leading/trailing whitespace from the whole block.
  final text = '''
${widget.event.name}

${widget.event.description.isNotEmpty ? widget.event.description : 'No description.'}

📅 $date
📍 ${widget.event.latitude.toStringAsFixed(5)}, ${widget.event.longitude.toStringAsFixed(5)}

Shared via Campus Vibes'''.trim();

  // Share.share() hands the text to the OS.
  // On iOS this opens the native share sheet (AirDrop, Messages, Mail, etc.)
  // On Android it opens the intent chooser.
  // subject is used by Mail apps as the email subject line.
  Share.share(text, subject: widget.event.name);
}
```

---

### Step 3 — Share Button in AppBar

```dart
AppBar(
  title: const Text('Event Details'),
  backgroundColor: Colors.orange,
  foregroundColor: Colors.white,
  actions: [
    IconButton(
      icon: const Icon(Icons.share),
      tooltip: 'Share event',
      onPressed: _onShareTapped,
    ),
  ],
)
```

---

## 6. Save / Favorites (#7)

### Concept

Users can bookmark events to a personal favorites list.
We store favorites in a **per-user subcollection** so each user's list is completely independent.

**Firestore structure:**
```
users/
  {userId}/
    favorites/
      {eventId}   ← document ID is the eventId
        name: "..."
        description: "..."
        ... (full event snapshot)
        savedAt: Timestamp
```

Storing a full event snapshot (instead of just the ID) lets the favorites tab
display event info without re-querying the events collection.

Using `eventId` as the document ID means saving the same event twice is a no-op —
`set()` silently overwrites instead of creating a duplicate.

We use a **live stream of saved event IDs** so when you bookmark something on the
detail screen, the card on the events list updates its bookmark icon instantly.

---

### Step 1 — Firestore Service Methods

```dart
// Shorthand reference to a user's favorites subcollection.
// Calling _favoritesRef(uid) gives us the CollectionReference without repeating the path.
CollectionReference _favoritesRef(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites');

// saveEvent — stores the full event data snapshot under favorites/{eventId}.
// The spread operator (...) copies all fields from event.toMap() into this document.
// savedAt records when the user bookmarked it (separate from the event's createdAt).
Future<void> saveEvent(String uid, Event event) async {
  await _favoritesRef(uid).doc(event.id).set({
    ...event.toMap(),
    'savedAt': FieldValue.serverTimestamp(),
  });
}

// unsaveEvent — removes the favorites document for this event.
Future<void> unsaveEvent(String uid, String eventId) async {
  await _favoritesRef(uid).doc(eventId).delete();
}

// checkEventSaved — one-time read. Returns true if the event is saved.
// Used to seed the bookmark icon state when the detail screen opens.
Future<bool> checkEventSaved(String uid, String eventId) async {
  final doc = await _favoritesRef(uid).doc(eventId).get();
  return doc.exists;
}

// getSavedEventIdsStream — live stream of which event IDs the user has saved.
// Returns a Set<String> so checking if an event is saved is O(1) — .contains()
// on a Set is instant regardless of how many events are saved.
Stream<Set<String>> getSavedEventIdsStream(String uid) {
  return _favoritesRef(uid).snapshots().map(
    // Each document's ID is the eventId — collect them into a Set.
    (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
  );
}
```

---

### Step 2 — Events Screen (converting to `StatefulWidget`)

The events screen needs to become a `StatefulWidget` to hold the two streams.

```dart
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  List<Event> _allEvents = [];

  // Set gives O(1) lookup — checking if an event is saved is just .contains()
  Set<String> _savedEventIds = {};
  bool _loading = true;

  // We keep subscriptions so we can cancel them in dispose().
  // Forgetting to cancel causes memory leaks and "setState after dispose" crashes.
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<Set<String>>? _savedSubscription;

  @override
  void initState() {
    super.initState();

    // Subscribe to all events — fires every time any event changes in Firestore.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      events.sort((a, b) => b.hypeCount.compareTo(a.hypeCount));
      setState(() {
        _allEvents = events;
        _loading = false;
      });
    });

    // Subscribe to saved IDs — fires when the user saves or unsaves anything.
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
    // Always cancel stream subscriptions when the widget is removed.
    _eventsSubscription?.cancel();
    _savedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleSave(Event event) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || event.id == null) return;

    if (_savedEventIds.contains(event.id)) {
      await _firestoreService.unsaveEvent(uid, event.id!);
    } else {
      await _firestoreService.saveEvent(uid, event);
    }
    // No setState needed — the stream fires and rebuilds automatically.
  }

  @override
  Widget build(BuildContext context) {
    // Split events into three sections.
    final savedEvents = _allEvents.where((e) => _savedEventIds.contains(e.id)).toList();
    final popular    = _allEvents.where((e) => e.hypeCount >= 1).toList();
    final regular    = _allEvents.where((e) => e.hypeCount < 1).toList();

    final List<Widget> items = [];

    if (savedEvents.isNotEmpty) {
      items.add(const _SectionHeader(icon: Icons.bookmark, label: 'My Favorites'));
      for (final e in savedEvents) {
        items.add(_EventCard(
          event: e,
          isSaved: true,
          onSaveToggled: () => _toggleSave(e),
        ));
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: items,
      ),
    );
  }
}
```

---

### Step 3 — Bookmark Button on the Detail Screen

Add to `_EventDetailScreenState`:

```dart
bool _hasSaved = false; // loaded async in initState

@override
void initState() {
  super.initState();
  // ... other init ...
  _loadSavedStatus();
}

Future<void> _loadSavedStatus() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || widget.event.id == null) return;

  final hasSaved = await _firestoreService.checkEventSaved(widget.event.id!, uid);
  if (mounted) setState(() => _hasSaved = hasSaved);
}

Future<void> _onSaveTapped() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || widget.event.id == null) return;

  final wasSaved = _hasSaved;
  setState(() => _hasSaved = !wasSaved); // optimistic update

  try {
    if (wasSaved) {
      await _firestoreService.unsaveEvent(uid, widget.event.id!);
    } else {
      await _firestoreService.saveEvent(uid, widget.event);
    }
  } catch (_) {
    if (mounted) setState(() => _hasSaved = wasSaved); // roll back
  }
}
```

Add the bookmark button to AppBar actions:

```dart
actions: [
  IconButton(
    icon: Icon(_hasSaved ? Icons.bookmark : Icons.bookmark_border),
    tooltip: _hasSaved ? 'Remove from favorites' : 'Save to favorites',
    onPressed: _onSaveTapped,
  ),
  IconButton(
    icon: const Icon(Icons.share),
    onPressed: _onShareTapped,
  ),
],
```

---

## 7. Calendar View (#5)

### Concept

The calendar gives users a date-based view of events instead of the scrolling list.
The `table_calendar` package renders the monthly grid — we just feed it the events.

**How the event grouping works:**
Each event has a `createdAt` timestamp. We normalize it to midnight
(`DateTime(year, month, day)`) and use that as the map key. That way, two events
at different times on the same day land in the same bucket.

**Why normalize to midnight?**
`DateTime(2026, 4, 14, 9, 30)` and `DateTime(2026, 4, 14, 14, 0)` are NOT equal.
`DateTime(2026, 4, 14)` and `DateTime(2026, 4, 14)` ARE equal.
Normalizing makes the map key reliable regardless of event time.

---

### Step 1 — Create `lib/screens/calendar_screen.dart`

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/firestore_service.dart';
import 'event_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<List<Event>>? _eventsSubscription;

  // Map from a normalized date (midnight) to the events on that day.
  // Using a Map lets _getEventsForDay do O(1) lookup instead of scanning a list.
  Map<DateTime, List<Event>> _eventsByDay = {};

  DateTime _focusedDay = DateTime.now(); // which month the calendar is showing
  DateTime _selectedDay = DateTime.now(); // which day the user has tapped

  @override
  void initState() {
    super.initState();

    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      final Map<DateTime, List<Event>> grouped = {};
      for (final event in events) {
        // Normalize to midnight — removes time-of-day from the key.
        final day = DateTime(
          event.createdAt.year,
          event.createdAt.month,
          event.createdAt.day,
        );
        // putIfAbsent: if the key doesn't exist yet, create an empty list first.
        // Then add the event to whichever list belongs to that day.
        grouped.putIfAbsent(day, () => []).add(event);
      }
      setState(() => _eventsByDay = grouped);
    });
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  // Returns the list of events for a given day.
  // table_calendar calls this for every visible day to know where to draw dots.
  List<Event> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day); // normalize the lookup key too
    return _eventsByDay[key] ?? []; // ?? [] means return empty list if no events
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _getEventsForDay(_selectedDay);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Calendar',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- CALENDAR WIDGET ---
          Container(
            color: Colors.white,
            child: TableCalendar<Event>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,

              // selectedDayPredicate tells the calendar which day to highlight.
              // isSameDay handles edge cases like timezone differences.
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),

              // eventLoader is called for every visible day.
              // Returning a non-empty list causes a dot to appear under that day.
              eventLoader: _getEventsForDay,

              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay; // keep the month view in sync
                });
              },

              onPageChanged: (focusedDay) {
                // User swiped to a different month — update focused day
                // but don't change the selected day.
                _focusedDay = focusedDay;
              },

              calendarStyle: CalendarStyle(
                // The dot under days with events.
                markerDecoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                // The circle around the selected day.
                selectedDecoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                // Today shown lighter so it doesn't clash with the selected circle.
                todayDecoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),

              headerStyle: const HeaderStyle(
                formatButtonVisible: false, // hide the "2 weeks" / "month" toggle
                titleCentered: true,
              ),
            ),
          ),

          const Divider(height: 1),

          // --- SELECTED DAY LABEL ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat('MMMM d, yyyy').format(_selectedDay),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ),
          ),

          // --- EVENT LIST FOR SELECTED DAY ---
          Expanded(
            child: selectedEvents.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No events on this day',
                            style: TextStyle(color: Colors.grey, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: selectedEvents.length,
                    itemBuilder: (context, index) {
                      final event = selectedEvents[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.orange,
                            child: Icon(Icons.event, color: Colors.white, size: 20),
                          ),
                          title: Text(event.name,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: event.description.isNotEmpty
                              ? Text(event.description,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          // Tapping an event from the calendar opens the same
                          // detail screen used everywhere else.
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => EventDetailScreen(event: event)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

---

### Step 2 — Add Calendar Tab to `home_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'event_screen.dart';
import 'calendar_screen.dart'; // <-- new import
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const EventsScreen(),
    const MapScreen(),
    const CalendarScreen(), // <-- added
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month), label: 'Calendar'), // <-- added
        ],
      ),
    );
  }
}
```

---

## 8. Rating System (#23)

### Concept

Users can rate events 1–5 stars and leave an optional text review.
Ratings are stored in a subcollection so each user gets exactly one review per event.
The event document caches the average so cards can display it without reading the subcollection.

**Firestore structure:**
```
events/
  {eventId}/
    reviews/
      {userId}        ← one document per reviewer
        rating: 4
        comment: "Great event!"
        createdAt: Timestamp

    ratingSum: 32     ← running total of all stars given
    reviewCount: 8    ← how many reviews exist
    averageRating: 4.0  ← ratingSum / reviewCount (cached for fast display)
```

**Why store `ratingSum` separately?**
To update the average when a user edits their review, we need to:
`newAverage = (oldSum - oldRating + newRating) / reviewCount`

If we only stored the average, we couldn't reverse-engineer the sum.
`ratingSum` lets us recompute the average correctly without reading all reviews.

**Why a transaction?**
The review document and the event's `ratingSum` / `reviewCount` / `averageRating`
must update together. A transaction guarantees this — if either write fails,
neither happens. The counts stay accurate even with concurrent reviewers.

---

### Step 1 — Add Rating Fields to the Event Model

```dart
class Event {
  // ... existing fields ...

  // Cached average star rating. Updated by the submitReview transaction.
  // double because averages have decimals (e.g. 4.2).
  final double averageRating;

  // How many reviews have been submitted. Stored here so we can show
  // "4.2 ★ (12 reviews)" on the card without reading the subcollection.
  final int reviewCount;

  Event({
    // ... existing params ...
    this.averageRating = 0.0,
    this.reviewCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      // ... existing fields ...
      'averageRating': averageRating,
      'reviewCount': reviewCount,
    };
  }

  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      // ... existing fields ...
      averageRating: (data['averageRating'] ?? 0).toDouble(),
      reviewCount: (data['reviewCount'] ?? 0) as int,
    );
  }
}
```

---

### Step 2 — Firestore Service Methods

```dart
// submitReview — creates or updates a review and recomputes averageRating
// atomically on the event document.
Future<void> submitReview(
  String eventId,
  String uid,
  int rating, {
  String comment = '',
}) async {
  final eventRef  = _eventsCollection.doc(eventId);
  final reviewRef = eventRef.collection('reviews').doc(uid);

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    // We must read before any writes inside a transaction.
    final reviewSnap = await transaction.get(reviewRef);
    final eventSnap  = await transaction.get(eventRef);

    final eventData    = eventSnap.data() as Map<String, dynamic>? ?? {};
    final currentSum   = (eventData['ratingSum']   ?? 0) as num;
    final currentCount = (eventData['reviewCount'] ?? 0) as num;

    final int newSum;
    final int newCount;

    if (reviewSnap.exists) {
      // User already reviewed — adjust sum without changing the count.
      // This is why we store ratingSum: we can subtract the old rating
      // and add the new one, giving the correct new average.
      final oldRating = (reviewSnap.data() as Map<String, dynamic>)['rating'] as int;
      newSum   = currentSum.toInt() - oldRating + rating;
      newCount = currentCount.toInt(); // count stays the same
    } else {
      // First review from this user — increment both sum and count.
      newSum   = currentSum.toInt() + rating;
      newCount = currentCount.toInt() + 1;
    }

    // Recompute the average to cache on the event document.
    final double newAverage = newCount > 0 ? newSum / newCount : 0.0;

    // Write the review document (overwrites if it already exists).
    transaction.set(reviewRef, {
      'rating': rating,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update the event document with the new stats.
    transaction.update(eventRef, {
      'ratingSum': newSum,         // used for future average recalculation
      'reviewCount': newCount,     // total number of reviews
      'averageRating': newAverage, // the cached average shown on cards
    });
  });
}

// getUserReview — returns the current user's review data, or null if not reviewed.
// Used on screen open to pre-fill the star widget with their existing rating.
Future<Map<String, dynamic>?> getUserReview(String eventId, String uid) async {
  final doc = await _eventsCollection
      .doc(eventId)
      .collection('reviews')
      .doc(uid)
      .get();
  return doc.exists ? doc.data() : null;
}

// getReviewsStream — live stream of all reviews, newest first.
Stream<QuerySnapshot> getReviewsStream(String eventId) {
  return _eventsCollection
      .doc(eventId)
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .snapshots();
}
```

---

### Step 3 — Rating UI in `EventDetailScreen`

Add to `_EventDetailScreenState`:

```dart
// --- RATING STATE ---
int _myRating = 0;              // 0 = no star selected yet
bool _hasReviewed = false;      // true after a successful submission
bool _submittingReview = false; // true while waiting for Firestore
late double _averageRating;     // seeded from widget.event, updated after submit
late int _reviewCount;          // seeded from widget.event, updated after submit
final TextEditingController _commentController = TextEditingController();

@override
void initState() {
  super.initState();
  _averageRating = widget.event.averageRating;
  _reviewCount   = widget.event.reviewCount;
  _loadReviewStatus();
}

@override
void dispose() {
  _commentController.dispose(); // always dispose TextEditingControllers
  super.dispose();
}

// _loadReviewStatus reads the subcollection to check if this user has reviewed.
// If they have, we pre-fill their stars and comment so they can edit it.
Future<void> _loadReviewStatus() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || widget.event.id == null) return;

  final review = await _firestoreService.getUserReview(widget.event.id!, uid);
  if (mounted && review != null) {
    setState(() {
      _hasReviewed = true;
      _myRating = (review['rating'] as int?) ?? 0;
      _commentController.text = (review['comment'] as String?) ?? '';
    });
  }
}

Future<void> _submitReview() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || widget.event.id == null || _myRating == 0) return;

  // Capture the messenger BEFORE the first await.
  // After an await, the widget may have been removed and 'context' is invalid.
  final messenger = ScaffoldMessenger.of(context);

  setState(() => _submittingReview = true);

  try {
    await _firestoreService.submitReview(
      widget.event.id!,
      uid,
      _myRating,
      comment: _commentController.text,
    );

    if (!mounted) return;
    setState(() {
      _hasReviewed = true;
      _submittingReview = false;
    });

    // Re-read the event doc to get the freshly computed average.
    final updatedSnap = await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.event.id)
        .get();
    if (mounted && updatedSnap.exists) {
      final data = updatedSnap.data()!;
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

Rating UI — add this to the build Column, after the attendee list:

```dart
// Gate: only show rating UI after the event date has passed.
// widget.event.createdAt is always in the past, so all events are reviewable.
// Swap createdAt for an eventDate field if you add one to the model later.
if (widget.event.id != null &&
    widget.event.createdAt.isBefore(DateTime.now())) ...[
  const Divider(),
  const SizedBox(height: 8),

  // Average rating summary — only shown when reviews exist.
  if (_reviewCount > 0)
    Row(
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 20),
        const SizedBox(width: 4),
        Text(_averageRating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text('($_reviewCount ${_reviewCount == 1 ? 'review' : 'reviews'})',
            style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    ),
  const SizedBox(height: 12),

  // Submit / edit review form (only when logged in).
  if (FirebaseAuth.instance.currentUser != null) ...[
    Text(
      _hasReviewed ? 'Your Review' : 'Rate This Event',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),

    // 5-star tap row — List.generate creates 5 star icons.
    Row(
      children: List.generate(5, (i) {
        final star = i + 1;
        return GestureDetector(
          onTap: () => setState(() => _myRating = star),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              // If _myRating is 3, stars 1-3 are filled, 4-5 are outlined.
              _myRating >= star ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 32,
            ),
          ),
        );
      }),
    ),
    const SizedBox(height: 10),

    // Optional comment text field.
    TextField(
      controller: _commentController,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: 'Leave a comment (optional)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(12),
      ),
    ),
    const SizedBox(height: 10),

    SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        // Disabled (null onPressed) until a star is selected.
        onPressed: (_myRating == 0 || _submittingReview) ? null : _submitReview,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _submittingReview
            ? const SizedBox(
                height: 18, width: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(_hasReviewed ? 'Update Review' : 'Submit Review'),
      ),
    ),
    const SizedBox(height: 16),
  ],

  // Expandable review list — only shown when reviews exist.
  if (_reviewCount > 0)
    _ReviewList(eventId: widget.event.id!, firestoreService: _firestoreService),
],
```

---

### Step 4 — Review List Widget

```dart
// _ReviewList shows all reviews in a collapsible ExpansionTile.
// StreamBuilder keeps it live — new reviews appear without refreshing.
class _ReviewList extends StatelessWidget {
  final String eventId;
  final FirestoreService firestoreService;

  const _ReviewList({required this.eventId, required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.rate_review, color: Colors.amber),
        title: const Text('Reviews',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getReviewsStream(eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Colors.amber),
                );
              }

              final reviews = snapshot.data?.docs ?? [];

              if (reviews.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reviews yet.', style: TextStyle(color: Colors.grey)),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final data = reviews[index].data() as Map<String, dynamic>;
                  final rating  = (data['rating']  as int?)    ?? 0;
                  final comment = (data['comment'] as String?)?.trim() ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display the star rating as a row of filled/outlined icons.
                        Row(
                          children: List.generate(5, (i) => Icon(
                            i < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          )),
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(comment,
                              style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
```

---

### Step 5 — Star Rating Badge on Event Cards

In `_EventCardState.build()`, add a star badge to the card's bottom info row:

```dart
// Show the average star rating if at least one review exists.
// toStringAsFixed(1) formats 4.1666... as "4.2"
if (widget.event.reviewCount > 0)
  Row(
    children: [
      const Icon(Icons.star, color: Colors.amber, size: 14),
      const SizedBox(width: 2),
      Text(
        widget.event.averageRating.toStringAsFixed(1),
        style: const TextStyle(
          fontSize: 12,
          color: Colors.amber,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 8),
    ],
  ),
```

---

## Key Patterns Reference

| Pattern | Where used | Why |
|---|---|---|
| Optimistic update | Hype, RSVP, Save | UI feels instant; rolls back on failure |
| Firestore transaction | RSVP, Rating | Keeps count + subcollection in sync atomically |
| `FieldValue.arrayUnion/Remove` | Hype | Server-safe array mutation; prevents duplicates |
| `FieldValue.increment` | Hype, RSVP, Rating | Atomic counter; no race conditions |
| `StreamSubscription` + `dispose()` | Events screen, Calendar | Prevents memory leaks |
| `Set<String>` for IDs | Favorites | O(1) `.contains()` lookup |
| Normalize DateTime to midnight | Calendar | Reliable map key regardless of time-of-day |
| `mounted` check after `await` | All async state | Prevents setState on a disposed widget |
| Capture `ScaffoldMessenger` before `await` | Rating submit | Prevents invalid BuildContext after async gap |
