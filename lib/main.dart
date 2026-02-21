import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() async {
  // gotta make sure Flutter is fully initialized before messing with Mapbox
  WidgetsFlutterBinding.ensureInitialized();

  // set the access token for Mapbox API — need this before creating any map
  MapboxOptions.setAccessToken(
    "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ",
  );

  // launch the app
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // basic MaterialApp wrapper, just standard Flutter stuff
    return MaterialApp(
      title: 'Campus Vibes',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MapScreen(), // main map screen
    );
  }
}

class MapScreen extends StatefulWidget {
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap; // will hold the MapboxMap object once created
  PointAnnotationManager? _pointManager; // handles the markers

  // keep track of event info keyed by annotation id
  final Map<String, Map<String, String>> _markerInfo = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          // starting position on the map
          center: Point(coordinates: Position(-98.1722, 26.3017)),
          zoom: 14.5,
        ),
        onMapCreated: _onMapCreated, // fired once the map is ready
        onTapListener: (ctx) {
          // when user taps the map, grab the coordinates
          final coords = ctx.point.coordinates;
          _showAddDialog(coords); // pop up a dialog to add a new event
        },
      ),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // create a manager for point annotations (markers)
    _pointManager =
    await mapboxMap.annotations.createPointAnnotationManager();

    // hook up click listener on markers
    _pointManager?.addOnPointAnnotationClickListener(
      _MyPointClickListener((annotation) {
        // grab info for this annotation
        final info = _markerInfo[annotation.id];
        if (info != null) {
          // show a simple dialog with name + description
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(info['name']!),
              content: Text(info['desc']!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), // close dialog
                  child: Text("Close"),
                ),
              ],
            ),
          );
        }
      }),
    );
  }

  Future<void> _showAddDialog(Position coords) async {
    // temporary vars to hold user input
    String name = '';
    String desc = '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("New Event"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // basic input for event name
            TextField(
              decoration: InputDecoration(labelText: "Event Name"),
              onChanged: (val) => name = val,
            ),
            // basic input for description
            TextField(
              decoration: InputDecoration(labelText: "Description"),
              onChanged: (val) => desc = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _addMarker(coords, name, desc); // create the marker
              Navigator.pop(context); // close dialog
            },
            child: Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _addMarker(
      Position coords,
      String name,
      String desc,
      ) async {
    if (_pointManager == null) return; // just in case

    // create the annotation on the map
    final annotation = await _pointManager!.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: coords),
        textField: name, // currently using textField, can swap for icon later
      ),
    );

    // save the info so clicks can show dialog later
    _markerInfo[annotation.id] = {
      'name': name,
      'desc': desc,
    };
  }
}

// need a listener class because Mapbox expects a full class, not just a lambda
class _MyPointClickListener extends OnPointAnnotationClickListener {
  final Function(PointAnnotation) onClicked;
  _MyPointClickListener(this.onClicked);

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    // just forward the click to whatever callback we passed in
    onClicked(annotation);
  }
}