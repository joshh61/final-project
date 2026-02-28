import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
// For JSON encoding/decoding of the Directions API response
import 'dart:convert';
// For making HTTPS requests to the Mapbox Directions API
import 'package:http/http.dart' as http;
import 'live_navigation.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;

  // Manager for circle annotations (your event markers) [[Circle annotations](https://docs.mapbox.com/flutter/maps/examples/circle_annotations/)]
  CircleAnnotationManager? _circleManager;

  // Store event info keyed by circle annotation id
  final Map<String, Map<String, String>> _markerInfo = {};

  // IDs for the route source/layer (must be unique in the style) [[Work with layers](https://docs.mapbox.com/flutter/maps/guides/styles/work-with-layers/#add-a-layer-at-runtime)]
  static const _routeSourceId = "route-source";
  static const _routeLayerId = "route-layer";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          // Initial camera position over campus
          center: Point(coordinates: Position(-98.1722, 26.3017)),
          zoom: 14.5,
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "route",
            child: const Icon(Icons.alt_route),
            onPressed: _showSampleRoute,
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "liveNav",
            child: const Icon(Icons.navigation),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LiveNavigationScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // MapboxMap is created; set up annotations and tap handlers
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Create a CircleAnnotationManager to draw circle markers [[Circle annotations](https://docs.mapbox.com/flutter/maps/examples/circle_annotations/)]
    _circleManager =
    await mapboxMap.annotations.createCircleAnnotationManager();

    // When a circle is tapped, show its stored info
    _circleManager?.tapEvents(onTap: (circle) {
      final info = _markerInfo[circle.id];
      if (info != null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(info['name']!),
            content: Text(info['desc']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      }
    });
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
        lineColor: Colors.blue.value,
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
        {
          "type": "Feature",
          "properties": {},
          "geometry": geometry,
        }
      ]
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
              _addCircle(coords, name, desc);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // Create a circle annotation for the event and store its metadata
  Future<void> _addCircle(Position coords, String name, String desc) async {
    if (_circleManager == null) return;

    final circle = await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: coords),
        circleColor: Colors.blue.value,
        circleRadius: 12.0,
        isDraggable: false,
      ),
    );

    _markerInfo[circle.id] = {
      'name': name,
      'desc': desc,
    };
  }
}