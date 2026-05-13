import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/app_config.dart';
import '../logic/navigation_access_evaluator.dart';
import '../services/app_logger.dart';

import 'package:flutter/services.dart';

enum NavigationPhase {
  initializing,
  loadingRoute,
  tracking,
  rerouting,
  arrived,
  error,
}

class LiveNavigationScreen extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String eventName;

  const LiveNavigationScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.eventName,
  });

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen> {
  MapboxMap? _mapboxMap;

  String _currentIcon = "assets/pic1a.png";

  StreamSubscription<geo.Position>? _positionStream;

  static const _routeSourceId = 'live-route-source';
  static const _routeLayerId = 'live-route-layer';

  static const double fallbackStartLat = 26.30369;
  static const double fallbackStartLng = -98.17493;

  static const double _minMovementMeters = 2.0;

  static const double _offRouteThresholdMeters = 40.0;

  static const double _arrivalThresholdMeters = 12.0;

  static const Duration _rerouteCooldown = Duration(seconds: 20);

  static const Duration _directionsTimeout = Duration(seconds: 10);

  static const int _maxDirectionsAttempts = 3;

  List<List<double>> _fullRouteCoords = [];

  geo.Position? _lastAcceptedPosition;

  DateTime? _lastRerouteAt;

  int _lastClosestIndex = 0;

  NavigationPhase _phase = NavigationPhase.initializing;

  Set<NavigationStatusAction> _actions = {};

  String? _statusMessage;

  bool _styleArtifactsReady = false;

  bool _trackingStarted = false;

  late ViewportState _viewport;

  @override
  void initState() {
    super.initState();

    _viewport = CameraViewportState(
      center: Point(coordinates: Position(widget.destLng, widget.destLat)),
      zoom: 15,
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventName),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _chooseIcon,
        child: const Icon(Icons.image),
      ),

      body: Stack(
        children: [
          MapWidget(
            styleUri: MapboxStyles.STANDARD,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(widget.destLng, widget.destLat),
              ),
              zoom: 15,
            ),
            viewport: _viewport,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),

          if (_statusMessage != null ||
              _phase == NavigationPhase.loadingRoute ||
              _phase == NavigationPhase.initializing)
            _buildStatusCard(),

          if (_phase == NavigationPhase.arrived) _buildArrivalOverlay(),
        ],
      ),
    );
  }

  void _transitionToFollowPuck() {
    // ignore: experimental_member_use
    setStateWithViewportAnimation(() {
      _viewport = FollowPuckViewportState(
        zoom: 17.0,
        bearing: const FollowPuckViewportStateBearingHeading(),
        pitch: 50.0,
      );
    }, completion: (_) {});
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    AppLogger.info('Map created for live navigation', category: 'navigation');
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return;

    try {
      await _ensureRouteStyleArtifacts();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to initialize route source/layer',
        category: 'map',
        error: error,
        stackTrace: stackTrace,
      );
      _setStatus(
        'Map style failed to initialize route rendering.',
        actions: {NavigationStatusAction.retry},
      );
      return;
    }

    await _startNavigationFlow();
  }

  Future<void> _ensureRouteStyleArtifacts() async {
    if (_mapboxMap == null) return;

    _styleArtifactsReady = false;

    try {
      await _mapboxMap!.style.addSource(
        GeoJsonSource(
          id: _routeSourceId,
          data: '{"type":"FeatureCollection","features":[]}',
        ),
      );
    } catch (error) {
      if (!_isAlreadyExistsError(error)) rethrow;
      AppLogger.debug('Route source already exists in style', category: 'map');
    }

    try {
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: _routeLayerId,
          sourceId: _routeSourceId,
          lineColor: Colors.blue.toARGB32(),
          lineWidth: 5.0,
        ),
      );
    } catch (error) {
      if (!_isAlreadyExistsError(error)) rethrow;
      AppLogger.debug('Route layer already exists in style', category: 'map');
    }

    _styleArtifactsReady = true;
  }

  bool _isAlreadyExistsError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('already exists') ||
        (msg.contains('source') && msg.contains('exists')) ||
        (msg.contains('layer') && msg.contains('exists'));
  }

  Future<void> _startNavigationFlow() async {
    _setStateIfMounted(() {
      _phase = NavigationPhase.initializing;
    });
    _trackingStarted = false;

    final canUseLiveLocation = await _resolveLocationAccess();

    await _configureLocationPuck(canUseLiveLocation);

    if (!canUseLiveLocation) {
      _stopPositionTracking();
      await _updateMapWithCoords(const <List<double>>[]);
      _setStateIfMounted(() {
        _phase = NavigationPhase.error;
        _viewport = CameraViewportState(
          center: Point(coordinates: Position(widget.destLng, widget.destLat)),
          zoom: 15,
        );
      });
      return;
    }

    final routeLoaded = await _recalculateRoute(useDeviceLocation: true);
    if (!routeLoaded) {
      _stopPositionTracking();
      return;
    }

    _startPositionTracking();
    _trackingStarted = true;
    _clearStatus();
    _setStateIfMounted(() {
      _phase = NavigationPhase.tracking;
    });

    _transitionToFollowPuck();
  }

  Future<bool> _resolveLocationAccess() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();

    if (serviceEnabled && permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    final decision = NavigationAccessEvaluator.evaluate(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );

    if (decision.canUseLiveLocation) {
      _clearStatus();
      AppLogger.info('Location permission granted', category: 'permission');
      return true;
    }

    _setStatus(decision.message!, actions: decision.actions);
    AppLogger.warning(decision.message!, category: 'permission');
    return false;
  }

  Future<void> _configureLocationPuck(bool enabled) async {
    if (_mapboxMap == null) return;

    try {
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: enabled,
          puckBearingEnabled: enabled,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to update location puck settings',
        category: 'map',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _recalculateRoute({
    required bool useDeviceLocation,
    geo.Position? forcedStart,
  }) async {
    if (_mapboxMap == null || !_styleArtifactsReady) return false;

    _setStateIfMounted(() {
      _phase = NavigationPhase.loadingRoute;
    });

    double startLat = fallbackStartLat;
    double startLng = fallbackStartLng;

    if (forcedStart != null) {
      startLat = forcedStart.latitude;
      startLng = forcedStart.longitude;
    } else if (useDeviceLocation) {
      try {
        final position = await geo.Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 6),
        );
        startLat = position.latitude;
        startLng = position.longitude;
      } catch (error, stackTrace) {
        AppLogger.warning(
          'Failed to read current location',
          category: 'permission',
          error: error,
          stackTrace: stackTrace,
        );
        _setStatus(
          'Could not read your current location yet. Retry after GPS settles.',
          actions: {NavigationStatusAction.retry},
        );
        _setStateIfMounted(() {
          _phase = NavigationPhase.error;
        });
        return false;
      }
    }

    final routeCoords = await _fetchDirectionsCoordinates(
      startLat: startLat,
      startLng: startLng,
    );

    if (routeCoords == null || routeCoords.length < 2) {
      _setStatus(
        'Could not load a walkable route right now. Try again.',
        actions: {NavigationStatusAction.retry},
      );
      _setStateIfMounted(() {
        _phase = NavigationPhase.error;
      });
      return false;
    }

    _fullRouteCoords = routeCoords;
    _lastClosestIndex = 0;
    _lastAcceptedPosition = null;

    await _updateMapWithCoords(routeCoords);

    AppLogger.info(
      'Route loaded (${routeCoords.length} points)',
      category: 'navigation',
    );
    return true;
  }

  Future<List<List<double>>?> _fetchDirectionsCoordinates({
    required double startLat,
    required double startLng,
  }) async {
    if (AppConfig.mapboxAccessToken.isEmpty) {
      _setStatus(
        'Missing MAPBOX_ACCESS_TOKEN. Run with --dart-define to enable navigation.',
        actions: {NavigationStatusAction.retry},
      );
      return null;
    }

    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/'
      '$startLng,$startLat;${widget.destLng},${widget.destLat}'
      '?geometries=geojson&access_token=${AppConfig.mapboxAccessToken}',
    );

    Duration backoff = const Duration(milliseconds: 700);

    for (int attempt = 1; attempt <= _maxDirectionsAttempts; attempt++) {
      try {
        final response = await http.get(uri).timeout(_directionsTimeout);

        if (response.statusCode == 200) {
          final parsed = _extractRouteCoordinates(response.body);
          if (parsed == null) {
            _setStatus(
              'Directions response was invalid. Try again.',
              actions: {NavigationStatusAction.retry},
            );
            AppLogger.warning(
              'Directions API returned an invalid body',
              category: 'network',
            );
          }
          return parsed;
        }

        final retryable =
            response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;

        if (retryable && attempt < _maxDirectionsAttempts) {
          AppLogger.warning(
            'Retrying directions request after HTTP ${response.statusCode} (attempt $attempt)',
            category: 'network',
          );
          await Future.delayed(backoff);
          backoff = Duration(milliseconds: backoff.inMilliseconds * 2);
          continue;
        }

        _setStatus(
          'Could not fetch route (HTTP ${response.statusCode}).',
          actions: {NavigationStatusAction.retry},
        );
        AppLogger.warning(
          'Directions request failed with HTTP ${response.statusCode}',
          category: 'network',
        );
        return null;
      } on TimeoutException catch (error, stackTrace) {
        if (attempt < _maxDirectionsAttempts) {
          AppLogger.warning(
            'Directions request timed out, retrying (attempt $attempt)',
            category: 'network',
            error: error,
            stackTrace: stackTrace,
          );
          await Future.delayed(backoff);
          backoff = Duration(milliseconds: backoff.inMilliseconds * 2);
          continue;
        }
        _setStatus(
          'Route request timed out. Check your connection and retry.',
          actions: {NavigationStatusAction.retry},
        );
        AppLogger.error(
          'Directions request timed out after retries',
          category: 'network',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      } on SocketException catch (error, stackTrace) {
        _setStatus(
          'No network connection. Connect to the internet and retry.',
          actions: {NavigationStatusAction.retry},
        );
        AppLogger.error(
          'Directions request failed due to network error',
          category: 'network',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      } catch (error, stackTrace) {
        _setStatus(
          'Unexpected route error. Please retry.',
          actions: {NavigationStatusAction.retry},
        );
        AppLogger.error(
          'Unexpected directions request error',
          category: 'network',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    return null;
  }

  List<List<double>>? _extractRouteCoordinates(String body) {
    final decoded = json.decode(body);

    if (decoded is! Map<String, dynamic>) return null;

    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final route = routes.first;
    if (route is! Map<String, dynamic>) return null;

    final geometry = route['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return null;

    final parsed = <List<double>>[];
    for (final point in coordinates) {
      if (point is! List || point.length < 2) continue;
      final lng = point[0];
      final lat = point[1];
      if (lng is! num || lat is! num) continue;
      parsed.add([lng.toDouble(), lat.toDouble()]);
    }

    if (parsed.length < 2) return null;
    return parsed;
  }

  void _startPositionTracking() {
    _positionStream?.cancel();

    _positionStream =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
            distanceFilter: 3,
          ),
        ).listen(
          _updateRouteProgress,
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.warning(
              'Location stream error',
              category: 'permission',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
  }

  void _stopPositionTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _updateRouteProgress(geo.Position position) {
    if (_fullRouteCoords.length < 2 ||
        _mapboxMap == null ||
        _phase == NavigationPhase.loadingRoute ||
        !_trackingStarted) {
      return;
    }

    final last = _lastAcceptedPosition;
    if (last != null) {
      final movement = geo.Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );
      if (movement < _minMovementMeters) return;
    }

    _lastAcceptedPosition = position;

    final (closestIndex, minDistance) = _findClosestRoutePoint(position);
    _lastClosestIndex = closestIndex;

    final distanceToDestination = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      widget.destLat,
      widget.destLng,
    );

    if (distanceToDestination <= _arrivalThresholdMeters) {
      if (_phase != NavigationPhase.arrived) {
        _stopPositionTracking();
        _trackingStarted = false;
        _setStateIfMounted(() {
          _phase = NavigationPhase.arrived;
        });
        _clearStatus();
        AppLogger.info('User arrived at destination', category: 'navigation');
      }
      return;
    }

    if (minDistance > _offRouteThresholdMeters) {
      if (_canRerouteNow()) {
        unawaited(_rerouteFromPosition(position, minDistance));
      }
      return;
    }

    final remainingRoute = _fullRouteCoords.sublist(closestIndex);
    unawaited(_updateMapWithCoords(remainingRoute));
  }

  (int, double) _findClosestRoutePoint(geo.Position position) {
    double minDistance = double.infinity;
    int closestIndex = _lastClosestIndex;

    final startIndex = (_lastClosestIndex - 8).clamp(
      0,
      _fullRouteCoords.length - 1,
    );

    for (int i = startIndex; i < _fullRouteCoords.length; i++) {
      final coord = _fullRouteCoords[i];
      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        coord[1],
        coord[0],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return (closestIndex, minDistance);
  }

  bool _canRerouteNow() {
    if (!_trackingStarted) return false;
    if (_phase == NavigationPhase.rerouting) return false;
    if (_lastRerouteAt == null) return true;
    return DateTime.now().difference(_lastRerouteAt!) >= _rerouteCooldown;
  }

  Future<void> _rerouteFromPosition(
    geo.Position position,
    double offRouteMeters,
  ) async {
    _setStateIfMounted(() {
      _phase = NavigationPhase.rerouting;
    });
    _lastRerouteAt = DateTime.now();

    _setStatus(
      'You seem off route (~${offRouteMeters.toStringAsFixed(0)}m). Recalculating...',
    );

    AppLogger.warning(
      'Off-route detected at ${offRouteMeters.toStringAsFixed(1)}m; rerouting',
      category: 'navigation',
    );

    final rerouted = await _recalculateRoute(
      useDeviceLocation: false,
      forcedStart: position,
    );

    _setStateIfMounted(() {
      _phase = NavigationPhase.tracking;
    });
    if (rerouted) {
      _clearStatus();
    } else {
      _setStatus(
        'Could not refresh the route right now. Keeping your current path.',
        actions: {NavigationStatusAction.retry},
      );
    }
  }

  Future<void> _updateMapWithCoords(List<List<double>> coords) async {
    if (_mapboxMap == null || !_styleArtifactsReady) return;

    final normalizedCoords = coords.length == 1
        ? [coords.first, coords.first]
        : coords;

    final routeGeoJson = coords.isEmpty
        ? '{"type":"FeatureCollection","features":[]}'
        : json.encode({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'properties': {},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': normalizedCoords,
                },
              },
            ],
          });

    try {
      await _mapboxMap!.style.setStyleSourceProperty(
        _routeSourceId,
        'data',
        routeGeoJson,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to update route source data',
        category: 'map',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _chooseIcon() async {
    if (_mapboxMap == null) return;

    setState(() {
      _currentIcon = _currentIcon == "assets/pic1a.png"
          ? "assets/pic1b.png"
          : "assets/pic1a.png";
    });

    final ByteData bytes = await rootBundle.load(_currentIcon);

    final Uint8List imageData = bytes.buffer.asUint8List();

    _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(topImage: imageData),
        ),
      ),
    );
  }

  Future<void> _onRetryPressed() async {
    await _startNavigationFlow();
  }

  Future<void> _openAppSettings() async {
    await geo.Geolocator.openAppSettings();
  }

  Future<void> _openLocationSettings() async {
    await geo.Geolocator.openLocationSettings();
  }

  void _setStatus(
    String message, {
    Set<NavigationStatusAction> actions = const {},
  }) {
    _setStateIfMounted(() {
      _statusMessage = message;
      _actions = actions;
    });
  }

  void _clearStatus() {
    _setStateIfMounted(() {
      _statusMessage = null;
      _actions = const {};
    });
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Widget _buildStatusCard() {
    final showSpinner =
        _phase == NavigationPhase.initializing ||
        _phase == NavigationPhase.loadingRoute ||
        _phase == NavigationPhase.rerouting;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: Card(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSpinner)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 4),
                ),

              if (_statusMessage != null)
                Text(_statusMessage!, style: const TextStyle(fontSize: 13.5)),

              if (_actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_actions.contains(NavigationStatusAction.retry))
                        OutlinedButton.icon(
                          onPressed: _onRetryPressed,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                      if (_actions.contains(
                        NavigationStatusAction.openAppSettings,
                      ))
                        OutlinedButton.icon(
                          onPressed: _openAppSettings,
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('App Settings'),
                        ),
                      if (_actions.contains(
                        NavigationStatusAction.openLocationSettings,
                      ))
                        OutlinedButton.icon(
                          onPressed: _openLocationSettings,
                          icon: const Icon(Icons.location_searching, size: 16),
                          label: const Text('Location Services'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArrivalOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 72),
                  const SizedBox(height: 16),

                  Text(
                    widget.eventName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You have arrived!',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Done', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
