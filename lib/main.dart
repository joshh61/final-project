import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NOTE: in production, pass this via --dart-define as in the docs.
  MapboxOptions.setAccessToken(
    "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ",
  );

  runApp(MyApp());
}

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

class MapScreen extends StatefulWidget {
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleManager;
  final Map<String, Map<String, String>> _markerInfo = {};

  // IDs for the route source/layer
  static const _routeSourceId = "route-source";
  static const _routeLayerId = "route-layer";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(-98.1722, 26.3017)),
          zoom: 14.5,
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: _onStyleLoaded, // hook to add route source/layer
        onTapListener: (ctx) {
          final coords = ctx.point.coordinates;
          _showAddDialog(coords);
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.alt_route),
        onPressed: _showSampleRoute,
      ),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    _circleManager =
    await mapboxMap.annotations.createCircleAnnotationManager();

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

  // Called when the style is loaded; set up a source + line layer for routes.
  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return;

    // Add an (initially empty) GeoJSON source for the route
    await _mapboxMap!.style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        data:
        '{"type":"FeatureCollection","features":[]}', // empty to start [[Route line example](https://docs.mapbox.com/flutter/maps/examples/route_line/)]
      ),
    );

    // Add a line layer that will draw whatever is in that source
    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: Colors.blue.value,
        lineWidth: 4.0,
      ),
    );
  }

  // For now: show a hard-coded route between two points near your campus.
  Future<void> _showSampleRoute() async {
    if (_mapboxMap == null) return;

    // Simple LineString GeoJSON between two coordinates
    const routeGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {},
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-98.1722, 26.3017],
          [-98.1700, 26.3030]
        ]
      }
    }
  ]
}
''';

    await _mapboxMap!.style.setStyleSourceProperty(
      _routeSourceId,
      "data",
      routeGeoJson,
    );
  }

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