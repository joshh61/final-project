import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/home_screen.dart';

// For JSON encoding/decoding of the Directions API response
import 'dart:convert';
// For making HTTPS requests to the Mapbox Directions API
import 'package:http/http.dart' as http;
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
import 'models/event_category.dart';

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

  // Last batch of events from Firestore — cached so the filter bar can
  // redraw markers without waiting for the next stream emission.
  List<Event> _cachedEvents = [];

  // Which categories are currently visible on the map.
  // Starts as all categories selected (show everything).
  Set<EventCategory> _visibleCategories = EventCategory.values.toSet();

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
      body: Stack(
        children: [
          MapWidget(
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
              _showAddDialog(coords);
            },
          ),
          // Category filter bar overlaid at the top of the map.
          // Positioned fills the full width; taps are consumed by the chips
          // so they don't fall through to the map's onTapListener.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildMapFilterBar(),
          ),
        ],
      ),
      // Sample route FAB for demo purposes
      floatingActionButton: FloatingActionButton(
        heroTag: "route",
        onPressed: _showSampleRoute,
        child: const Icon(Icons.alt_route),
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

  // Clears all circle markers and redraws only the categories that are
  // currently selected in the filter bar.
  Future<void> _redrawMarkers(List<Event> events) async {
    // Always cache the full list so the filter bar can redraw without
    // waiting for the next Firestore stream emission.
    _cachedEvents = events;
    if (_circleManager == null) return;

    await _circleManager!.deleteAll();
    _circleToEvent.clear();

    // Only draw markers whose category is toggled on.
    final visible = events.where((e) => _visibleCategories.contains(e.category));

    for (final event in visible) {
      // Color the circle by category — each category has its own distinct hue
      // defined in EventCategory.color.
      final circle = await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: event.category.color.toARGB32(),
          circleRadius: 12.0,
          isDraggable: false,
        ),
      );
      _circleToEvent[circle.id] = event;
    }
  }

  // Called when a filter chip is tapped on the map.
  // Toggles the category's visibility and redraws the markers immediately.
  void _toggleCategory(EventCategory cat) {
    setState(() {
      if (_visibleCategories.contains(cat)) {
        _visibleCategories.remove(cat);
      } else {
        _visibleCategories.add(cat);
      }
    });
    // Redraw with the cached list — no need to wait for a new Firestore event.
    _redrawMarkers(_cachedEvents);
  }

  // Builds the horizontal scrollable chip bar that sits at the top of the map.
  Widget _buildMapFilterBar() {
    return Container(
      color: Colors.white.withValues(alpha: 0.93),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: EventCategory.values.map((cat) {
            final selected = _visibleCategories.contains(cat);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: Icon(cat.icon,
                    size: 14, color: selected ? Colors.white : cat.color),
                label: Text(cat.label),
                selected: selected,
                onSelected: (_) => _toggleCategory(cat),
                selectedColor: cat.color,
                backgroundColor: Colors.grey.shade100,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
                showCheckmark: false,
                side: BorderSide(color: cat.color, width: 1.5),
              ),
            );
          }).toList(),
        ),
      ),
    );
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

    // Same public access token you used for the map
    final accessToken =
        "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ";

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
    image_picker.XFile? pickedImage;
    bool isFree = true;
    EventCategory category = EventCategory.other;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("New Event"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: "Event Name"),
                  onChanged: (val) => name = val,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: "Description"),
                  onChanged: (val) => desc = val,
                ),
                const SizedBox(height: 12),
                // Category picker — InputDecorator gives us the same outlined
                // border as the TextFields above while letting DropdownButton
                // stay controlled (value: drives the displayed selection after
                // each setDialogState call, which DropdownButtonFormField's
                // deprecated value: also did but with a lint warning).
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<EventCategory>(
                      value: category,
                      isDense: true,
                      isExpanded: true,
                      items: EventCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Row(
                            children: [
                              Icon(cat.icon, size: 16, color: cat.color),
                              const SizedBox(width: 8),
                              Text(cat.label,
                                  style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(
                          () => category = val ?? EventCategory.other),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Free / Paid toggle — Switch is the clearest binary input
                // for a single boolean; label updates to reflect current state.
                Row(
                  children: [
                    Text(
                      isFree ? 'Free Event' : 'Paid Event',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isFree ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: isFree,
                      onChanged: (val) => setDialogState(() => isFree = val),
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red.shade400,
                      inactiveTrackColor: Colors.red.shade100,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (pickedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(pickedImage!.path),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text("Remove photo"),
                    onPressed: () => setDialogState(() => pickedImage = null),
                  ),
                ] else
                  TextButton.icon(
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text("Add Photo"),
                    onPressed: () async {
                      final image = await image_picker.ImagePicker()
                          .pickImage(source: image_picker.ImageSource.gallery, imageQuality: 80);
                      if (image != null) {
                        setDialogState(() => pickedImage = image);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _saveEvent(coords, name, desc, pickedImage, isFree, category);
              },
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );
  }

  // Save event to Firestore. The stream listener will automatically
  // pick up the new event and draw it on the map.
  Future<void> _saveEvent(
      Position coords, String name, String desc,
      image_picker.XFile? imageFile, bool isFree, EventCategory category) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _firestoreService.uploadEventImage(imageFile);
    }
    final event = Event(
      name: name,
      description: desc,
      latitude: coords.lat.toDouble(),
      longitude: coords.lng.toDouble(),
      imageUrl: imageUrl,
      isFree: isFree,
      category: category,
    );
    await _firestoreService.addEvent(event);
  }
}
