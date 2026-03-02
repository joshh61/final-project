import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

class LiveNavigationScreen extends StatefulWidget {
  const LiveNavigationScreen({Key? key}) : super(key: key);

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen> {
  MapboxMap? _mapboxMap; //store the map object once it's created so we can talk to it later

  static const _routeSourceId = "live-route-source"; // id for the geojson source that holds the line data
  static const _routeLayerId = "live-route-layer"; // id for the visual line layer drawn on the map

  //hard coded destination route
  //eventually, this will take the place of event coordinates
  static const double destLat = 26.18878;
  static const double destLng = -98.23584;

  //fallback START coordinates in case GPS fails or the device is far from start
  static const double fallbackStartLat = 26.30597;
  static const double fallbackStartLng = -98.17355;

  //creating our access token
  final String accessToken =
      "pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ";

  List<List<double>> _fullRouteCoords = []; // holds the entire route we get from Mapbox directions API
  StreamSubscription<geo.Position>? _positionStream; // listens to device GPS updates

  @override
  void dispose() {
    _positionStream?.cancel(); // stop listening to GPS when screen is closed to save battery
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold( // scaffold is our main screen layout: appbar + body
      appBar: AppBar(title: const Text("Live Walking Navigation")),
      body: MapWidget(
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(destLng, destLat)), // start map centered on destination
          zoom: 15, //good level for walking visiblity
        ),
        onMapCreated: _onMapCreated, //callback when map finishes initializing
        onStyleLoadedListener: _onStyleLoaded, // callback when map style (roads, colors) is fully loaded
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap; // save the reference so we can manipulate map later

    await geo.Geolocator.requestPermission(); // ask user for GPS access

    // enable the live blue puck (user location marker) and allow it to rotate according to heading
    await mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return; // safety check

    // create an empty geojson source to hold our route line
    // this source is what the layer will reference to draw the line

    await _mapboxMap!.style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        data: '{"type":"FeatureCollection","features":[]}', // empty to start
      ),
    );

    // create a line layer to draw the route on top of the map
    // connecting this layer to the source means updating the source updates the line automatically
    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: Colors.blue.value,
        lineWidth: 5.0,
      ),
    );

    // fetch the walking route once from current location to destination
    // API call done once to avoid spamming and inefficiency
    await _fetchInitialRoute();

    // start listening to GPS updates
    // as the user moves, we trim the route so the line appears to shrink dynamically
    _positionStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best, // high accuracy for walking
        distanceFilter: 3, // update every ~3 meters
      ),
    ).listen(_updateRouteProgress);
  }

  Future<void> _fetchInitialRoute() async {
    if (_mapboxMap == null) return;

    double startLat = fallbackStartLat;
    double startLng = fallbackStartLng;

    try {
      final geo.Position position =
      await geo.Geolocator.getCurrentPosition(); // get real device location

      startLat = position.latitude;
      startLng = position.longitude;
    } catch (_) {} // if GPS fails, we fall back to default start

    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "$startLng,$startLat;$destLng,$destLat"
        "?geometries=geojson&access_token=$accessToken";

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return; // stop if server error

    final data = json.decode(response.body);
    if (data["routes"] == null || data["routes"].isEmpty) return; // stop if no route returned

    final geometry = data["routes"][0]["geometry"];

    // Mapbox returns a List<dynamic> but Dart wants List<double>
    // convert nested list of coordinates to List<List<double>> for type safety
    _fullRouteCoords = (geometry["coordinates"] as List)
        .map((coord) => (coord as List).map((e) => (e as num).toDouble()).toList())
        .toList();

    // push full route to map so it draws initially
    _updateMapWithCoords(_fullRouteCoords);
  }

  void _updateRouteProgress(geo.Position position) {
    if (_fullRouteCoords.isEmpty || _mapboxMap == null) return;

    double minDistance = double.infinity;
    int closestIndex = 0;

    // loop through every point in the route
    // find the point closest to the user's current GPS location
    // this lets us know how much of the route the user has already walked
    for (int i = 0; i < _fullRouteCoords.length; i++) {
      final coord = _fullRouteCoords[i];

      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        coord[1],
        coord[0],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i; // remember index of closest point
      }
    }

    // remove all points behind the user so the line "shrinks" as they walk
    final remainingRoute = _fullRouteCoords.sublist(closestIndex);
    _updateMapWithCoords(remainingRoute);
  }

  void _updateMapWithCoords(List<List<double>> coords) async {
    // convert the coordinates into a GeoJSON FeatureCollection
    // this is the format Mapbox expects for drawing lines
    final routeGeoJson = json.encode({
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": coords, // actual line points
          },
        }
      ]
    });

    // push the updated geojson to the map source
    // Mapbox redraws the line automatically whenever the source changes
    await _mapboxMap!.style.setStyleSourceProperty(
      _routeSourceId,
      "data",
      routeGeoJson,
    );
  }
}