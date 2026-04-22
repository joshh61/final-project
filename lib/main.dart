import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/home_screen.dart';

// For JSON encoding/decoding of the Directions API response
// For making HTTPS requests to the Mapbox Directions API
import 'package:firebase_auth/firebase_auth.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/event_detail_screen.dart';
// Firebase initialization
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// Firestore service and Event model
import 'services/firestore_service.dart';
import 'models/event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase FIRST
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set your Mapbox public access token before creating any maps.
  // In production, Mapbox recommends passing this via --dart-define. [[Flutter examples](https://docs.mapbox.com/flutter/maps/examples/)]
  //^to be fixed, it is not ideal to push keys publicly (though our repo is private right now)
  MapboxOptions.setAccessToken(
    "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ",
  );

  runApp(MyApp());
}

// Standard Flutter root widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Vibes',
      theme: ThemeData(primarySwatch: Colors.blue),
      // Check auth state and show appropriate screen
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Still loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // User is logged in - show map
          if (snapshot.hasData) {
            return HomeScreen();
          }

          // User is NOT logged in - show login screen
          return LoginScreen();
        },
      ),
    );
  }
}

// Screen that hosts the Mapbox map
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const int _maxEventTitleLength = 30;
  static const int _maxEventDescriptionLength = 225;

  bool _isWithinEventCreationBounds(Position coords) { //for event creation, technicality (not precise but accurate)
    return coords.lat >= 26.30273 &&
        coords.lat <= 26.31152 &&
        coords.lng >= -98.18600 &&
        coords.lng <= -98.16800;
  }

  MapboxMap? _mapboxMap;

  // Manager for circle annotations (your event markers)
  CircleAnnotationManager? _circleManager;

  // Firestore service — handles all database operations
  final FirestoreService _firestoreService = FirestoreService();

  // Stream subscription for real-time Firestore updates.
  // Cancel in dispose() to prevent memory leaks.
  StreamSubscription? _eventsSubscription;

  // Maps circle annotation ID → Event object for tap lookups
  final Map<String, Event> _circleToEvent = {};

  // IDs for the route source/layer (must be unique in the style)
  static const _routeSourceId = "route-source";
  static const _routeLayerId = "route-layer";

  // Map center (adjusted for better campus view)
  static const double utrgvCenterLat = 26.3050;
  static const double utrgvCenterLng = -98.1740;

  // Only render tiles within this radius - improves performance
  static const double horizontalRadius = 0.012;
  static const double verticalRadius = 0.010;

  // Map boundaries
  static const double southwestLat = utrgvCenterLat - verticalRadius;
  static const double southwestLng = utrgvCenterLng - horizontalRadius;
  static const double northeastLat = utrgvCenterLat + verticalRadius;
  static const double northeastLng = utrgvCenterLng + horizontalRadius;

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Campus Map'),
        backgroundColor: Colors.orange,
        actions: [
          // Logout button
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: MapWidget(
        cameraOptions: CameraOptions(
          // Initial camera position over campus
          center: Point(coordinates: Position(utrgvCenterLng, utrgvCenterLat)),
          zoom: 15.5,
        ),
        // Called once the MapboxMap object is ready
        onMapCreated: _onMapCreated,
        // Called when the style is fully loaded; you add sources/layers here
        onStyleLoadedListener: _onStyleLoaded,
        // Tap on the map to add a new event marker
        onTapListener: (ctx) {
          final coords = ctx.point.coordinates;

          if (!_isWithinEventCreationBounds(coords)) { //restricting the user
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Events can only be created inside campus event bounds'),
              ),
            );
            return;
          }


          _showAddDialog(coords);
        },
      ),
    );
  }

  // MapboxMap is created; set up annotations and tap handlers
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Keep map focused on campus area - don't load unnecessary tiles
    await mapboxMap.setBounds(
      CameraBoundsOptions(
        bounds: CoordinateBounds(
          southwest: Point(coordinates: Position(southwestLng, southwestLat)),
          northeast: Point(coordinates: Position(northeastLng, northeastLat)),
          infiniteBounds: false,
        ),
        maxZoom: 18.0,
        minZoom: 15.0,
      ),
    );

    // Create a CircleAnnotationManager to draw circle markers [[Circle annotations](https://docs.mapbox.com/flutter/maps/examples/circle_annotations/)]
    _circleManager = await mapboxMap.annotations
        .createCircleAnnotationManager();

    // When a circle is tapped, navigate to the EventDetailScreen
    _circleManager?.tapEvents(
      onTap: (circle) {
        final event = _circleToEvent[circle.id];
        if (event != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
          );
        }
      },
    );

    // Listen to Firestore for real-time event updates.
    // Every time the 'events' collection changes, redraw all markers.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _redrawMarkers(events);
    });
  }

  // Clears all circle markers and redraws them from Firestore data.
  Future<void> _redrawMarkers(List<Event> events) async {
    if (_circleManager == null) return;

    await _circleManager!.deleteAll();
    _circleToEvent.clear();

    for (final event in events) {
      final circle = await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: Colors.blue.toARGB32(),
          circleRadius: 12.0,
          isDraggable: false,
        ),
      );
      _circleToEvent[circle.id] = event;
    }
  }

  // Called when the style is loaded; set up a GeoJSON source + line layer for routes.
  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return;

    // 1) Add an (initially empty) GeoJSON source for the route.
    // This matches the pattern in the official GeoJSON line example. [[GeoJSON line example](https://docs.mapbox.com/flutter/maps/examples/geojson_line/)]
    await _mapboxMap!.style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        // Start with an empty FeatureCollection; we'll replace "data" later.
        data: '{"type":"FeatureCollection","features":[]}',
      ),
    );

    // 2) Add a LineLayer that draws whatever geometry is in the route source. [[Work with layers](https://docs.mapbox.com/flutter/maps/guides/styles/work-with-layers/#add-a-layer-at-runtime)]
    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: Colors.blue.toARGB32(),
        lineWidth: 4.0,
      ),
    );
  }

  // Dialog to add a new event marker at the tapped coordinates
  Future<void> _showAddDialog(Position coords) async {
    String name = '';
    String desc = '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Event"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: "Event Name"),
              onChanged: (val) => name = val,
            ),
            TextField(
              decoration: const InputDecoration(labelText: "Description"),
              onChanged: (val) => desc = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {

              final trimmedName = name.trim();
              final trimmedDesc = desc.trim();

              if (trimmedName.isEmpty || trimmedDesc.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Title and description cannot be empty')),
                );
                return;
              }

              if (trimmedName.length > _maxEventTitleLength) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Title must be $_maxEventTitleLength characters or less',
                    ),
                  ),
                );
                return;
              }

              if (trimmedDesc.length > _maxEventDescriptionLength) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Description must be $_maxEventDescriptionLength characters or less',
                    ),
                  ),
                );
                return;
              }

              _saveEvent(coords, trimmedName, trimmedDesc);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // Save event to Firestore. The stream listener will automatically
  // pick up the new event and draw it on the map.
  Future<void> _saveEvent(Position coords, String name, String desc) async {

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .where('createdBy', isEqualTo: uid)
        .get();

    if (snapshot.docs.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You can only create 3 events")),
      );
      return;
    }


    final event = Event(
      name: name,
      description: desc,
      latitude: coords.lat.toDouble(),
      longitude: coords.lng.toDouble(),
      createdBy: uid,
    );
    await _firestoreService.addEvent(event);
  }
}
