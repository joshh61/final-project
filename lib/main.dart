import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
// For JSON encoding/decoding of the Directions API response
import 'dart:convert';
// For making HTTPS requests to the Mapbox Directions API
import 'package:http/http.dart' as http;
// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// Our Firestore service and Event model
import 'services/firestore_service.dart';
import 'models/event.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before anything else
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set your Mapbox public access token before creating any maps.
  // In production, Mapbox recommends passing this via --dart-define. [[Flutter examples](https://docs.mapbox.com/flutter/maps/examples/)]
  //^to be fixed, it is not ideal to push keys publicly (though our repo is private right now)
  String accessToken = const String.fromEnvironment("ACCESS_TOKEN");
  MapboxOptions.setAccessToken(accessToken);

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
      home: MapScreen(),
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
  MapboxMap? _mapboxMap;

  // Manager for circle annotations (your event markers)
  CircleAnnotationManager? _circleManager;

  // Firestore service — handles all database operations
  final FirestoreService _firestoreService = FirestoreService();

  // Stream subscription — we listen to Firestore for real-time event updates.
  // Like an event listener in JS: we need to cancel it when the widget is
  // removed from the screen, otherwise it keeps listening in the background
  // and leaks memory.
  StreamSubscription? _eventsSubscription;

  // Local copy of events from Firestore, used to look up event info
  // when a circle marker is tapped. Maps circle annotation ID → Event object.
  final Map<String, Event> _circleToEvent = {};

  // IDs for the route source/layer (must be unique in the style)
  static const _routeSourceId = "route-source";
  static const _routeLayerId = "route-layer";

  // OPTIMIZATION: UTRGV center coordinates (adjusted for better centering)
  static const double utrgvCenterLat = 26.3050;
  static const double utrgvCenterLng = -98.1740;

  // OPTIMIZATION: Custom radius to restrict map bounds (improves performance)
  // Only renders tiles within this radius, reducing memory and bandwidth usage
  static const double horizontalRadius = 0.012; // ~0.85 miles east-west
  static const double verticalRadius = 0.010; // ~0.7 miles north-south

  // OPTIMIZATION: Calculate bounds from center and radius
  static const double southwestLat = utrgvCenterLat - verticalRadius;
  static const double southwestLng = utrgvCenterLng - horizontalRadius;
  static const double northeastLat = utrgvCenterLat + verticalRadius;
  static const double northeastLng = utrgvCenterLng + horizontalRadius;

  @override
  void dispose() {
    // Cancel the Firestore stream when this screen is removed.
    // Like removeEventListener() in JS — prevents memory leaks.
    _eventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          // Initial camera position over campus (OPTIMIZED: centered on UTRGV)
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
          _showAddDialog(coords);
        },
      ),
      // FAB triggers the walking route request + drawing
      floatingActionButton: FloatingActionButton(
        onPressed: _showSampleRoute,
        child: const Icon(Icons.alt_route),
      ),
    );
  }

  // MapboxMap is created; set up annotations, tap handlers, and Firestore listener
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // OPTIMIZATION: Restrict map to UTRGV campus area for better performance
    // Prevents loading unnecessary tiles outside campus vicinity
    await mapboxMap.setBounds(
      CameraBoundsOptions(
        bounds: CoordinateBounds(
          southwest: Point(coordinates: Position(southwestLng, southwestLat)),
          northeast: Point(coordinates: Position(northeastLng, northeastLat)),
          infiniteBounds: false,
        ),
        maxZoom: 18.0, // Can zoom in to see building details
        minZoom: 15.0, // Can't zoom out past full campus view
      ),
    );

    // Create a CircleAnnotationManager to draw circle markers
    _circleManager = await mapboxMap.annotations
        .createCircleAnnotationManager();

    // When a circle is tapped, look up the Event from our local map
    // and show its info. This used to use _markerInfo (raw strings),
    // now it uses _circleToEvent (proper Event objects from Firestore).
    _circleManager?.tapEvents(
      onTap: (circle) {
        final event = _circleToEvent[circle.id];
        if (event != null) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(event.name),
              content: Text(event.description),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          );
        }
      },
    );

    // Start listening to Firestore for events.
    // Every time the 'events' collection changes (add/update/delete),
    // this callback fires with the full updated list of events.
    // We clear all existing circles and redraw them from the new data.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _redrawMarkers(events);
    });
  }

  // Clears all circle markers and redraws them from the Firestore data.
  // Called every time the Firestore stream emits new data.
  Future<void> _redrawMarkers(List<Event> events) async {
    if (_circleManager == null) return;

    // Remove all existing circles from the map
    await _circleManager!.deleteAll();
    _circleToEvent.clear();

    // Draw a circle for each event from Firestore
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
      // Map this circle's ID to its Event so we can look it up on tap
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

  // Heart of the walking path logic:
  // - Call Mapbox Directions API with the walking profile
  // - Extract the route geometry (GeoJSON LineString)
  // - Wrap it in a FeatureCollection
  // - Feed it into the GeoJsonSource so the LineLayer draws it
  Future<void> _showSampleRoute() async {
    if (_mapboxMap == null) return;

    // Hard-coded origin and destination (lng, lat) near campus
    const startLng = -98.17355;
    const startLat = 26.30597;

    const endLng = -98.17636;
    const endLat = 26.30722;

    // Get access token from environment
    final accessToken = const String.fromEnvironment("ACCESS_TOKEN");

    // Directions API URL:
    // - profile: mapbox/walking (pedestrian routing profile) [[routing profile](https://docs.mapbox.com/help/glossary/routing-profile/)]
    // - coordinates: startLng,startLat;endLng,endLat
    // - geometries=geojson so the route geometry is returned as a GeoJSON LineString
    //   which you can plug directly into a GeoJSON source. [[Directions playground](https://docs.mapbox.com/playground/directions/)]
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "$startLng,$startLat;$endLng,$endLat"
        "?geometries=geojson&access_token=$accessToken";

    // Make the HTTP GET request to the Directions API
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      // Basic error logging if the API call fails
      print("Directions API error: ${response.body}");
      return;
    }

    // Parse the JSON response
    final data = json.decode(response.body);

    // Directions response structure:
    // routes[0].geometry holds the route geometry.
    // With geometries=geojson, this is a GeoJSON LineString object. [[Navigation APIs webinar](https://www.youtube.com/watch?v=kfrR0OLBcNE)]
    final geometry = data["routes"][0]["geometry"];

    // Wrap the LineString geometry in a FeatureCollection so it matches
    // what a GeoJsonSource expects. [[GeoJSON line example](https://docs.mapbox.com/flutter/maps/examples/geojson_line/)]
    final routeGeoJson = json.encode({
      "type": "FeatureCollection",
      "features": [
        {"type": "Feature", "properties": {}, "geometry": geometry},
      ],
    });

    // Update the existing GeoJsonSource's "data" property with the new route.
    // The LineLayer is already wired to this source, so the map updates automatically. [[Work with layers](https://docs.mapbox.com/flutter/maps/guides/styles/work-with-layers/#add-a-layer-at-runtime)]
    await _mapboxMap!.style.setStyleSourceProperty(
      _routeSourceId,
      "data",
      routeGeoJson,
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
              _saveEvent(coords, name, desc);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // Save event to Firestore instead of just storing in memory.
  // We DON'T need to manually draw the circle here anymore —
  // the Firestore stream listener (_redrawMarkers) will pick up
  // the new event automatically and draw it for us.
  Future<void> _saveEvent(Position coords, String name, String desc) async {
    final event = Event(
      name: name,
      description: desc,
      latitude: coords.lat.toDouble(),
      longitude: coords.lng.toDouble(),
    );
    await _firestoreService.addEvent(event);
  }
}
