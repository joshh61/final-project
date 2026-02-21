import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken("pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ");
  runApp(MyApp());
  
  
  
  
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Vibes',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(-98.1722, 26.3017)),
          zoom: 14.5,
          bearing: -161.81,
          pitch: 70,
        ),
      ),
    );
  }
}

