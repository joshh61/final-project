import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo; // For getting device GPS location
import 'package:http/http.dart' as http; // For making HTTP requests to Mapbox Directions API
import 'dart:convert'; //JSON parsing

class LiveNavigationScreen extends StatefulWidget {
  const LiveNavigationScreen({Key? key}) : super(key: key);

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen> {
  MapboxMap? _mapboxMap;

  static const _routeSourceId = "live-route-source";
  static const _routeLayerId = "live-route-layer";

  //  Destination your requested point
  //26.18878° N, 98.23584° W test coords, la plaza mall mcallen
  static const double destLat = 26.18878;
  static const double destLng = -98.23584;

  //  Fallback start location (near campus) in case device location is far or unavailable
  static const double fallbackStartLat = 26.30597;
  static const double fallbackStartLng = -98.17355;

  // Mapbox access token
  final String accessToken =
      "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Walking Navigation")),
      body: MapWidget( // Initial camera options: center at destination, zoom level 15
      cameraOptions: CameraOptions(
          center: Point(coordinates: Position(destLng, destLat)),
          zoom: 15,
        ),
        onMapCreated: _onMapCreated, // called when map object is ready
        onStyleLoadedListener: _onStyleLoaded, // called when map style is ready
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.directions_walk),
        onPressed: _drawRoute, // draws route when button clicked
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Request permission for user location
    geo.LocationPermission permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      print("Location permission denied. Using fallback start location.");
    }

    //Enable live blue puck
    await mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
      ),
    );

    // Slight delay to ensure style + location ready
    Future.delayed(const Duration(seconds: 2), () {
      _drawRoute();
    });
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return;

    // Add an empty GeoJSON source for our route
    await _mapboxMap!.style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        data: '{"type":"FeatureCollection","features":[]}',
      ),
    );

    //Add a line layer that will display the route
    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: Colors.blue.value, // line color
        lineWidth: 5.0, // line thickness
      ),
    );
  }

  //Main function to request and draw walking route
  Future<void> _drawRoute() async {
    if (_mapboxMap == null) return;

    double startLat = fallbackStartLat;
    double startLng = fallbackStartLng;

    //Try to get device current location
    try {
      final geo.Position position = await geo.Geolocator.getCurrentPosition();
      print("Device location: ${position.latitude}, ${position.longitude}");

      //Calculate distance from current location to destination
      final distanceMeters = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        destLat,
        destLng,
      );

      if (distanceMeters <= 20000) { // ≤20 km, safe for walking API
        startLat = position.latitude;
        startLng = position.longitude;
      } else {
        print( //dummy fallback option in case too far
            "Device too far from destination (${(distanceMeters / 1000).toStringAsFixed(1)} km). Using fallback start point.");
      }
    } catch (e) {
      print("Failed to get device location: $e. Using fallback start point.");
    }

    //Build the Mapbox Directions API URL
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "$startLng,$startLat;$destLng,$destLat"
        "?geometries=geojson&access_token=$accessToken";

    //Send HTTP GET request
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) { //error fallback
      print("Directions error: ${response.body}");
      return;
    }

    //Parse the JSON response and extract route geometry
    final data = json.decode(response.body);
    final geometry = data["routes"][0]["geometry"]; // GeoJSON line

    //Wrap geometry in a FeatureCollection (needed by Mapbox layer)
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

    //Update the source data, Mapbox redraws the line layer automatically
    await _mapboxMap!.style.setStyleSourceProperty(
      _routeSourceId,
      "data",
      routeGeoJson,
    );
  }
}