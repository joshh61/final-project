import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set your Mapbox API token before creating any maps
  MapboxOptions.setAccessToken(
    "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ",
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Standard MaterialApp wrapper
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

  // now using CircleAnnotationManager instead of point annotations
  CircleAnnotationManager? _circleManager;

  // store event info keyed by circle annotation id
  final Map<String, Map<String, String>> _markerInfo = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          // starting view
          center: Point(coordinates: Position(-98.1722, 26.3017)),
          zoom: 14.5,
        ),
        onMapCreated: _onMapCreated,
        // listen for taps to add new events
        onTapListener: (ctx) {
          final coords = ctx.point.coordinates;
          _showAddDialog(coords);
        },
      ),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // create a circle manager — this lets us draw circle annotations instead of pins
    _circleManager = await mapboxMap.annotations.createCircleAnnotationManager();

    // tap listener for circles
    _circleManager?.tapEvents(onTap: (circle) {
      final info = _markerInfo[circle.id];
      if (info != null) {
        // show dialog with event name/description
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(info['name']!),
            content: Text(info['desc']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Close"),
              ),
            ],
          ),
        );
      }
    });
  }

  Future<void> _showAddDialog(Position coords) async {
    String name = '';
    String desc = '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("New Event"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(labelText: "Event Name"),
              onChanged: (val) => name = val,
            ),
            TextField(
              decoration: InputDecoration(labelText: "Description"),
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
            child: Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _addCircle(Position coords, String name, String desc) async {
    if (_circleManager == null) return;

    // create the circle annotation — visually a simple colored circle
    final circle = await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: coords),
        circleColor: Colors.blue.value, // can be customized per event
        circleRadius: 12.0,
        isDraggable: false,
      ),
    );

    // save its data for taps
    _markerInfo[circle.id] = {
      'name': name,
      'desc': desc,
    };
  }
}