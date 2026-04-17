// ─────────────────────────────────────────────────────────────────────────────
// LiveNavigationScreen
// ─────────────────────────────────────────────────────────────────────────────
//
// This screen shows a live walking route from the user's GPS position to an
// event location. It draws a blue line on the Mapbox map and shrinks that line
// as the user walks — exactly like Google Maps walking mode.
//
// HOW IT WORKS (big picture, step by step):
//   1. Map finishes loading → ask the phone for GPS permission
//   2. Get current GPS position → call Mapbox Directions API for a walking route
//   3. Draw the route as a blue line on the map
//   4. Start a continuous GPS stream that fires every time the user moves
//   5. Each GPS update → trim the blue line behind the user, check if off-route,
//      check if arrived
//   6. Off-route (more than 40 m from the line) → fetch a new route automatically
//   7. Within 12 m of the destination → show "You have arrived!" overlay
//
// KEY DART/FLUTTER CONCEPTS USED HERE:
//   - StatefulWidget   : widget whose data changes over time
//   - async / await    : how Dart waits for slow work (GPS, network) without freezing the UI
//   - Stream           : a continuous feed of values over time (like a GPS position feed)
//   - StreamSubscription: the "ticket" that lets us listen to a stream and cancel it later
//   - enum             : a fixed list of named values used as a state machine
//   - Stack            : Flutter widget that layers children on top of each other
//   - GeoJSON          : the data format Mapbox uses to draw shapes on a map

import 'dart:async';    // StreamSubscription — lets us listen to ongoing GPS updates
import 'dart:convert';  // json.decode / json.encode — reads and writes JSON text
import 'dart:io';       // SocketException — the error type thrown when there is no internet

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo; // GPS position + permission handling
import 'package:http/http.dart' as http;             // makes HTTP network requests
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'; // Mapbox map + camera

import '../config/app_config.dart';                        // Mapbox token + dev flags
import '../logic/navigation_access_evaluator.dart';        // GPS permission logic
import '../services/app_logger.dart';                      // debug logging

import 'package:flutter/services.dart'; // for rootBundle and ByteData (editing live nav icon pucks)

// ─── NavigationPhase enum ─────────────────────────────────────────────────────
//
// An enum (short for "enumeration") is a type that can only be one of a fixed
// set of named values. Think of it like a traffic light: it can only be
// red, yellow, or green — nothing else.
//
// We use NavigationPhase as a "state machine". At any moment the screen is in
// exactly ONE of these phases, and we use that to decide what to show the user.
//
// Without an enum we would use raw Strings like "loading" or "tracking", which
// are error-prone (a typo like "loding" would silently do nothing).
// Enums are safe: the compiler catches misspelled phase names immediately.
enum NavigationPhase {
  initializing, // the map just loaded — we are setting up GPS and checking permissions
  loadingRoute, // we are calling the Mapbox Directions API, waiting for the route data
  tracking,     // route is drawn and the GPS stream is running — the user is walking
  rerouting,    // the user went off-route; we are fetching a new route right now
  arrived,      // the user is within 12 m of the destination
  error,        // something failed (no GPS, no internet, etc.)
}

// ─── LiveNavigationScreen (the widget) ───────────────────────────────────────
//
// StatefulWidget means this widget has STATE — data that changes over time.
// The screen starts in "initializing" and moves through multiple phases,
// updating the route line, status messages, and camera as it goes.
// A StatelessWidget could not handle that — it has no memory of changes.
class LiveNavigationScreen extends StatefulWidget {

  // These three fields are passed in from EventDetailScreen when the user taps
  // "Get Directions". They are final (read-only) because the destination
  // does not change once the screen opens.

  final double destLat;   // GPS latitude of the event  (e.g. 26.30369)
  final double destLng;   // GPS longitude of the event (e.g. -98.17493)
  final String eventName; // shown in the AppBar and the arrival card

  // const constructor — "const" means the widget can be created at compile time
  // if all its values are known. Not required, but a Flutter best practice.
  // super.key passes the key up to the parent StatefulWidget class.
  const LiveNavigationScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.eventName,
  });

  // createState() is called once by Flutter to build the mutable State object.
  // The State object is where all our changing data and methods live.
  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

// ─── _LiveNavigationScreenState (the state) ──────────────────────────────────
//
// This class holds all the changing data and all the logic.
// The underscore prefix (_) makes it private — only this file can see it.
// "extends State<LiveNavigationScreen>" means: this is the state for LiveNavigationScreen.
//
// Inside here we can access:
//   widget.destLat / widget.destLng / widget.eventName  — data from the widget
//   setState(() { ... })  — tell Flutter to rebuild the UI with new data
//   mounted  — true while the widget is visible; false after the user goes back
class _LiveNavigationScreenState extends State<LiveNavigationScreen> {

  // --- MAPBOX MAP REFERENCE ---
  // MapboxMap? — the ? means this can be null.
  // It starts as null because the map is not ready yet when initState() runs.
  // The map calls _onMapCreated() once it is set up, which fills this in.
  MapboxMap? _mapboxMap;

  String _currentIcon = "assets/pic1a.png";

  // --- GPS STREAM SUBSCRIPTION ---
  // A Stream is like a river of values over time. Geolocator.getPositionStream()
  // returns a Stream<geo.Position> that emits a new Position every time the
  // user moves.
  //
  // StreamSubscription is the "ticket" we get when we start listening.
  // We MUST keep it and call .cancel() in dispose() — otherwise the GPS
  // keeps running after the screen is gone, draining the battery and potentially
  // calling setState on a widget that no longer exists (which crashes the app).
  StreamSubscription<geo.Position>? _positionStream;

  // --- MAPBOX LAYER / SOURCE IDs ---
  // In Mapbox, you draw things in two steps:
  //   1. Add a "source" — this holds the raw data (our route coordinates as GeoJSON)
  //   2. Add a "layer" — this tells Mapbox HOW to draw that data (blue line, 5px thick)
  //
  // We give each one a unique string ID so we can find and update them later.
  // static const = shared by all instances of this class, never changes.
  static const _routeSourceId = 'live-route-source';
  static const _routeLayerId  = 'live-route-layer';

  // --- CAMPUS FALLBACK POSITION ---
  // If we cannot read the user's real GPS position (timeout, weak signal),
  // we start the route from this point near UTRGV campus instead of crashing.
  static const double fallbackStartLat = 26.30369;
  static const double fallbackStartLng = -98.17493;

  // --- NAVIGATION THRESHOLDS ---
  // These constants control when certain events happen.
  // Keeping them at the top as named constants makes them easy to tune later.

  // Minimum meters the user must move before we process a GPS update.
  // GPS hardware "wobbles" — even standing still it may report tiny position changes.
  // Without this filter, we would redraw the route dozens of times per second for no reason.
  static const double _minMovementMeters = 2.0;

  // How far off the route (in meters) before we call this "off-route" and recalculate.
  // 40 m gives the user room to walk on a sidewalk slightly beside the route line.
  static const double _offRouteThresholdMeters = 40.0;

  // How close to the destination (in meters) counts as "arrived".
  // 12 m is roughly the width of a building entrance — close enough.
  static const double _arrivalThresholdMeters = 12.0;

  // After rerouting, wait this long before allowing another reroute.
  // Without this cooldown, if the new route is also slightly off, we might
  // reroute again and again in a rapid loop.
  // Duration is a Dart built-in type that represents a span of time.
  static const Duration _rerouteCooldown = Duration(seconds: 20);

  // How long to wait for the Directions API before giving up on that attempt.
  static const Duration _directionsTimeout = Duration(seconds: 10);

  // How many times to retry the Directions API before showing an error.
  static const int _maxDirectionsAttempts = 3;

  // --- ROUTE STATE ---

  // The complete list of [longitude, latitude] points that make up the walking route.
  // Example: [[−98.174, 26.303], [−98.175, 26.304], ...]
  // Note: Mapbox uses [lng, lat] order (longitude first), NOT the usual [lat, lng].
  // As the user walks, we remove points from the front of this list.
  List<List<double>> _fullRouteCoords = [];

  // The last GPS position we actually used (after the min-movement filter).
  // geo.Position? — nullable because there is no previous position on first update.
  geo.Position? _lastAcceptedPosition;

  // When did we last reroute? Compared against _rerouteCooldown to prevent rapid reroutes.
  // DateTime? — nullable because we have never rerouted when the screen first opens.
  DateTime? _lastRerouteAt;

  // Index into _fullRouteCoords of the route point closest to the user right now.
  // We use this to trim the route — everything before this index is behind the user.
  // Starts at 0 (beginning of the route).
  int _lastClosestIndex = 0;

  // --- UI STATE ---

  // The current phase of the navigation flow (see enum above).
  // Starts in "initializing" — changes as the flow progresses.
  NavigationPhase _phase = NavigationPhase.initializing;

  // Which buttons to show in the status card (Retry, App Settings, etc.)
  // Set<NavigationStatusAction> — a Set because order doesn't matter and duplicates
  // are impossible. {} = empty set (no buttons shown by default).
  Set<NavigationStatusAction> _actions = {};

  // The error/status message shown in the status card.
  // String? — nullable because null means "no message, don't show the card".
  String? _statusMessage;

  // --- INTERNAL FLAGS ---

  // true once we have successfully added the GeoJSON source + line layer to the map.
  // We must NOT try to draw the route before these exist or Mapbox will crash.
  bool _styleArtifactsReady = false;

  // true once the GPS position stream has been started.
  // Guards against processing GPS events that arrive before the route is ready.
  bool _trackingStarted = false;

  // --- CAMERA / VIEWPORT STATE ---
  // ViewportState controls where the Mapbox camera is looking.
  // "late" means: "I promise to set this before anyone reads it."
  // We set it in initState(), which runs immediately, so it is always initialized.
  //
  // We start with a fixed camera pointed at the destination, then switch to
  // "follow puck" once tracking starts (camera follows the user's location dot).
  late ViewportState _viewport;

  // ─── LIFECYCLE METHODS ────────────────────────────────────────────────────────
  //
  // Flutter calls these methods automatically at specific points in the widget's life.
  // The order is always: initState → build (many times) → dispose.

  @override
  void initState() {
    super.initState(); // always call super first in lifecycle methods

    // Set the initial camera viewport to look at the destination.
    // Position(lng, lat) — note Mapbox is longitude-first.
    // zoom: 15 is roughly street-level.
    _viewport = CameraViewportState(
      center: Point(coordinates: Position(widget.destLng, widget.destLat)),
      zoom: 15,
    );
  }

  @override
  void dispose() {
    // dispose() is called when the user navigates away from this screen.
    //
    // CRITICAL: always cancel streams in dispose().
    // If you skip this, the GPS stream keeps running even after the screen is gone.
    // That means:
    //   - Battery drain (GPS runs 24/7 for no reason)
    //   - Potential crash ("setState called on a disposed widget")
    //
    // The ?. is the "null-safe call" operator.
    // _positionStream?.cancel() means:
    //   "if _positionStream is not null, call .cancel() on it"
    //   "if it IS null, do nothing" (avoids a null pointer crash)
    _positionStream?.cancel();
    super.dispose(); // always call super last in dispose
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────
  //
  // build() returns the widget tree — the description of what appears on screen.
  // Flutter calls this every time setState() is called.
  // It should be fast and pure (no network calls, no timers).

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventName), // widget.eventName reads from the parent widget
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),

      floatingActionButton: FloatingActionButton( //button to to toggle icons
        onPressed: _chooseIcon,
        child: const Icon(Icons.image),
      ),

      // Stack layers its children like a stack of papers.
      // First child goes at the bottom; each subsequent child sits on top.
      // Here: map → status card → arrival overlay (from back to front).
      body: Stack(
        children: [

          // ── MAP (bottom layer) ────────────────────────────────────────────
          MapWidget(
            styleUri: MapboxStyles.STANDARD, // which map visual theme to use
            cameraOptions: CameraOptions(
              // Start the camera pointed at the destination.
              center: Point(
                coordinates: Position(widget.destLng, widget.destLat),
              ),
              zoom: 15,
            ),
            viewport: _viewport,                   // controlled programmatically
            onMapCreated: _onMapCreated,           // fires when the SDK is ready
            onStyleLoadedListener: _onStyleLoaded, // fires when tiles + fonts are loaded
          ),

          // ── STATUS CARD (middle layer, shown conditionally) ───────────────
          // The if() inside a list is how Flutter conditionally includes widgets.
          // If the condition is false, the widget is simply not built — no empty space.
          //
          // Show the card while:
          //   - there is a status/error message to display, OR
          //   - we are in a phase that implies loading (spinner)
          if (_statusMessage != null ||
              _phase == NavigationPhase.loadingRoute ||
              _phase == NavigationPhase.initializing)
            _buildStatusCard(),

          // ── ARRIVAL OVERLAY (top layer, shown when arrived) ───────────────
          if (_phase == NavigationPhase.arrived) _buildArrivalOverlay(),
        ],
      ),
    );
  }

  // ─── MAP EVENT HANDLERS ───────────────────────────────────────────────────────

  // _transitionToFollowPuck switches the camera into "navigation mode":
  // the map rotates to always show what is ahead, and tilts 50° for a 3D view.
  // This is called once tracking starts — before that, the camera stays on the destination.
  void _transitionToFollowPuck() {
    // ignore: experimental_member_use
    setStateWithViewportAnimation(
      () {
        _viewport = FollowPuckViewportState(
          zoom: 17.0, // closer zoom so the user can see nearby streets
          // FollowPuckViewportStateBearingHeading = rotate the map to match the
          // direction the user is walking (heading). Without this, north is always up.
          bearing: const FollowPuckViewportStateBearingHeading(),
          pitch: 50.0, // 50° tilt gives the perspective "driving game" look
        );
      },
      completion: (_) {}, // nothing special to do when the animation finishes
    );
  }

  // ─── NAVIGATION FLOW ──────────────────────────────────────────────────────────

  // _onMapCreated is called once by the Mapbox SDK when the map object is ready.
  // At this point the map EXISTS but has not loaded any tiles or styles yet.
  // We just save the reference — we cannot draw anything yet.
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    AppLogger.info('Map created for live navigation', category: 'navigation');
  }

  // _onStyleLoaded is called once the map style has fully loaded:
  // tiles, fonts, icons, layers — everything is ready.
  // This is the earliest point at which we can safely add our own sources and layers.
  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return; // safety check — should not happen

    try {
      // Add the empty GeoJSON source + blue line layer that we will use to draw the route.
      await _ensureRouteStyleArtifacts();
    } catch (error, stackTrace) {
      // error  = what went wrong
      // stackTrace = the chain of function calls that led to the error (for debugging)
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

    // Both the source and layer are ready — begin the full navigation flow.
    await _startNavigationFlow();
  }

  // _ensureRouteStyleArtifacts adds the GeoJSON source and line layer to the map style.
  //
  // In Mapbox everything drawn on the map follows this pattern:
  //   Source = the data container (GeoJSON text describing where to draw)
  //   Layer  = the visual style rule (how to draw the source: blue line, 5px thick)
  //
  // We add them ONCE. Later we only update the data inside the source.
  // Mapbox automatically redraws the layer whenever the source data changes.
  Future<void> _ensureRouteStyleArtifacts() async {
    if (_mapboxMap == null) return;

    _styleArtifactsReady = false;

    // -- ADD SOURCE --
    // GeoJSON is a standard text format for geographic shapes.
    // We start with an empty FeatureCollection (no route yet).
    // '{"type":"FeatureCollection","features":[]}' = valid GeoJSON with zero features.
    try {
      await _mapboxMap!.style.addSource(
        GeoJsonSource(
          id: _routeSourceId,
          data: '{"type":"FeatureCollection","features":[]}',
        ),
      );
    } catch (error) {
      // Mapbox throws an error if you try to add a source that already exists.
      // This can happen if the map style reloads (e.g. when the app returns from background).
      // In that case, we simply skip adding it — it is already there.
      if (!_isAlreadyExistsError(error)) rethrow; // rethrow = pass the error up if unexpected
      AppLogger.debug('Route source already exists in style', category: 'map');
    }

    // -- ADD LAYER --
    // LineLayer tells Mapbox: "draw the source data as a line on the map."
    // lineColor must be an ARGB integer — toARGB32() converts a Flutter Color to that format.
    // lineWidth is in pixels.
    try {
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: _routeLayerId,
          sourceId: _routeSourceId, // connect this layer to our source
          lineColor: Colors.blue.toARGB32(),
          lineWidth: 5.0,
        ),
      );
    } catch (error) {
      if (!_isAlreadyExistsError(error)) rethrow;
      AppLogger.debug('Route layer already exists in style', category: 'map');
    }

    _styleArtifactsReady = true; // safe to draw routes now
  }

  // Helper: checks if a Mapbox error is just "this source/layer already exists".
  // We inspect the error message as a String because Mapbox does not expose
  // specific error types for this case.
  //
  // .toLowerCase() makes the check case-insensitive — "Already Exists" and
  // "already exists" both match.
  bool _isAlreadyExistsError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('already exists') ||
        (msg.contains('source') && msg.contains('exists')) ||
        (msg.contains('layer') && msg.contains('exists'));
  }

  // _startNavigationFlow is the main sequence of steps to go from "map loaded"
  // to "user is walking with a live route on screen".
  //
  // async means this function contains await calls — it can pause and resume.
  // Each await pauses HERE until the awaited work finishes, but the rest of the
  // app keeps running (the UI does not freeze).
  Future<void> _startNavigationFlow() async {
    _setStateIfMounted(() {
      _phase = NavigationPhase.initializing;
    });
    _trackingStarted = false;

    // STEP 1: Check whether we can use the GPS at all.
    // _resolveLocationAccess() checks if location services are on and if the
    // user has granted location permission to this app.
    // It also shows the system permission dialog if needed.
    final canUseLiveLocation = await _resolveLocationAccess();

    // STEP 2: Show or hide the blue GPS "puck" dot on the map.
    await _configureLocationPuck(canUseLiveLocation);

    if (!canUseLiveLocation) {
      // Cannot navigate — clear the route line and stop here.
      // The error message was already set inside _resolveLocationAccess().
      _stopPositionTracking();
      await _updateMapWithCoords(const <List<double>>[]);
      _setStateIfMounted(() {
        _phase = NavigationPhase.error;
        // Reset the camera to look at the destination so at least the map is useful.
        _viewport = CameraViewportState(
          center: Point(coordinates: Position(widget.destLng, widget.destLat)),
          zoom: 15,
        );
      });
      return; // early return — do not proceed to step 3
    }

    // STEP 3: Fetch the walking route from Mapbox Directions API.
    // This calls the Directions API with the user's real GPS location as the start.
    final routeLoaded = await _recalculateRoute(useDeviceLocation: true);
    if (!routeLoaded) {
      _stopPositionTracking();
      return; // error message already set inside _recalculateRoute
    }

    // STEP 4: Start listening to continuous GPS position updates.
    // From this point on, _updateRouteProgress is called every time the user moves.
    _startPositionTracking();
    _trackingStarted = true;
    _clearStatus();
    _setStateIfMounted(() {
      _phase = NavigationPhase.tracking;
    });

    // STEP 5: Switch the camera into "follow puck" mode — it now tracks the user.
    _transitionToFollowPuck();
  }

  // _resolveLocationAccess checks GPS permission and returns true if navigation
  // is allowed, false otherwise.
  //
  // There are two separate things to check:
  //   1. Are Location Services ON in the phone's Settings? (system-wide toggle)
  //   2. Has the user granted THIS APP permission to use location?
  // Both must be true before we can get a GPS position.
  Future<bool> _resolveLocationAccess() async {
    // isLocationServiceEnabled() checks the system-level GPS switch.
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();

    // checkPermission() reads the current app permission WITHOUT showing a dialog.
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();

    // If permission is "denied" (user has not decided yet, OR previously tapped Deny),
    // we can still ask again. requestPermission() shows the system dialog.
    // We only ask if location services are actually on — no point asking if GPS is off.
    if (serviceEnabled && permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    // NavigationAccessEvaluator interprets the results and returns a decision.
    // This logic lives in a separate file so it is easy to test independently.
    final decision = NavigationAccessEvaluator.evaluate(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );

    if (decision.canUseLiveLocation) {
      _clearStatus();
      AppLogger.info('Location permission granted', category: 'permission');
      return true;
    }

    // decision.message describes what went wrong in plain English.
    // decision.actions is which buttons to show (Retry, Open Settings, etc.)
    _setStatus(decision.message!, actions: decision.actions);
    AppLogger.warning(decision.message!, category: 'permission');
    return false;
  }

  // _configureLocationPuck shows or hides the blue "you are here" dot on the map.
  // enabled = true  → show the dot and rotate it in the direction the user faces
  // enabled = false → hide it (no point showing "you are here" if we have no GPS)
  Future<void> _configureLocationPuck(bool enabled) async {
    if (_mapboxMap == null) return;

    try {
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: enabled,            // show/hide the puck dot
          puckBearingEnabled: enabled, // rotate the dot to face the direction of travel
        ),
      );
    } catch (error, stackTrace) {
      // Not a fatal error — the route will still work, the puck just might not show.
      AppLogger.warning(
        'Failed to update location puck settings',
        category: 'map',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // _recalculateRoute fetches a walking route from Mapbox and draws it on the map.
  //
  // useDeviceLocation = true  → ask the phone for the current GPS position as the start
  // forcedStart              → use this specific position (passed in when rerouting)
  //
  // Returns true if a route was successfully loaded, false on failure.
  Future<bool> _recalculateRoute({
    required bool useDeviceLocation, // required = caller MUST pass this
    geo.Position? forcedStart,       // optional — only used when rerouting
  }) async {
    if (_mapboxMap == null || !_styleArtifactsReady) return false;

    _setStateIfMounted(() {
      _phase = NavigationPhase.loadingRoute;
    });

    // Default start = campus fallback in case GPS is unavailable.
    double startLat = fallbackStartLat;
    double startLng = fallbackStartLng;

    if (forcedStart != null) {
      // Rerouting: use the exact position where the user went off-route.
      startLat = forcedStart.latitude;
      startLng = forcedStart.longitude;
    } else if (useDeviceLocation) {
      // Try to read the actual device GPS position.
      // getCurrentPosition() is async — it talks to the GPS hardware and waits.
      // timeLimit: 6 seconds — if GPS hasn't responded by then, we catch the timeout.
      try {
        final position = await geo.Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 6),
        );
        startLat = position.latitude;
        startLng = position.longitude;
      } catch (error, stackTrace) {
        // GPS read failed (could be timeout, permission revoked, hardware issue).
        // We fall back to the campus default above — the app still works, just less accurate.
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

    // Call the Mapbox Directions API to get a walking route.
    final routeCoords = await _fetchDirectionsCoordinates(
      startLat: startLat,
      startLng: startLng,
    );

    // A valid route needs at least 2 points. Null means the API call failed.
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

    // Save the full route. Reset the cursor to the beginning.
    _fullRouteCoords = routeCoords;
    _lastClosestIndex = 0;
    _lastAcceptedPosition = null;

    // Push the route coordinates into the Mapbox source so the blue line appears.
    await _updateMapWithCoords(routeCoords);

    AppLogger.info(
      'Route loaded (${routeCoords.length} points)',
      category: 'navigation',
    );
    return true;
  }

  // _fetchDirectionsCoordinates makes the actual HTTP GET request to the Mapbox API.
  //
  // Returns a List of [lng, lat] pairs tracing the walking path, or null on failure.
  //
  // The Mapbox Directions API URL format:
  //   /directions/v5/mapbox/walking/{startLng},{startLat};{destLng},{destLat}
  //   ?geometries=geojson   — return the route as GeoJSON (vs. polyline encoding)
  //   &access_token=...     — your Mapbox API key
  //
  // We retry up to _maxDirectionsAttempts times with "exponential backoff" —
  // each retry waits twice as long as the previous one (700ms, 1400ms, 2800ms).
  // This is standard practice for network requests that might temporarily fail.
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

    // Uri.parse() converts a string URL into a typed Uri object.
    // String interpolation ($variable) inserts the variable's value into the string.
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/'
      '$startLng,$startLat;${widget.destLng},${widget.destLat}'
      '?geometries=geojson&access_token=${AppConfig.mapboxAccessToken}',
    );

    // Start backoff at 700 ms. We double it on each retry (exponential backoff).
    Duration backoff = const Duration(milliseconds: 700);

    for (int attempt = 1; attempt <= _maxDirectionsAttempts; attempt++) {
      try {
        // http.get() sends the request. .timeout() sets a deadline.
        // If the server doesn't respond within _directionsTimeout, a TimeoutException is thrown.
        final response = await http.get(uri).timeout(_directionsTimeout);

        if (response.statusCode == 200) {
          // 200 = HTTP "OK" — the request succeeded.
          // Parse the JSON body and extract the route coordinates.
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
          return parsed; // return whether valid or null — both are handled by the caller
        }

        // These HTTP status codes mean a temporary server problem — worth retrying.
        //   429 = Rate limited (too many requests)
        //   500 = Internal server error
        //   502 = Bad gateway (a proxy between us and the server had an error)
        //   503 = Service unavailable (server overloaded)
        //   504 = Gateway timeout (a proxy timed out waiting for the server)
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
          // Future.delayed() pauses this function for the backoff duration.
          // Other code still runs while we wait — this is not a blocking sleep.
          await Future.delayed(backoff);
          backoff = Duration(milliseconds: backoff.inMilliseconds * 2); // double it
          continue; // jump back to the top of the for loop for the next attempt
        }

        // Non-retryable error (e.g. 401 Unauthorized, 404 Not Found) — give up.
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
        // The await http.get(...).timeout() threw this because the server didn't respond in time.
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
        // SocketException = no internet connection at all (airplane mode, no Wi-Fi).
        // No point retrying — the user needs to connect first.
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
        // Catch-all: something unexpected went wrong. Log it and give up.
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

    return null; // exhausted all attempts
  }

  // _extractRouteCoordinates parses the raw JSON response from the Directions API
  // and returns a list of [lng, lat] coordinate pairs.
  //
  // The API response structure looks like this (simplified):
  // {
  //   "routes": [
  //     {
  //       "geometry": {
  //         "type": "LineString",
  //         "coordinates": [
  //           [-98.174, 26.303],   ← [longitude, latitude]
  //           [-98.175, 26.304],
  //           ...
  //         ]
  //       }
  //     }
  //   ]
  // }
  //
  // json.decode() turns the JSON string into a Dart Map/List structure.
  // We then navigate that structure step by step, checking types at each level.
  // If anything is missing or the wrong type, we return null (caller shows an error).
  List<List<double>>? _extractRouteCoordinates(String body) {
    final decoded = json.decode(body); // convert JSON text → Dart object

    // is! checks the runtime type. If decoded is not a Map, return null.
    if (decoded is! Map<String, dynamic>) return null;

    // Navigate into the JSON structure safely.
    // Each step checks the type before going deeper — avoids null crashes.
    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final route = routes.first; // we only care about the best (first) route
    if (route is! Map<String, dynamic>) return null;

    final geometry = route['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return null;

    // Convert each coordinate from "dynamic" (unknown type) to List<double>.
    // "dynamic" is Dart's way of saying "I don't know the type yet."
    // We validate each point before adding it — bad data is silently skipped.
    final parsed = <List<double>>[];
    for (final point in coordinates) {
      if (point is! List || point.length < 2) continue; // skip malformed points
      final lng = point[0];
      final lat = point[1];
      if (lng is! num || lat is! num) continue; // skip if not numbers
      // .toDouble() converts int or double to double (our list requires double).
      parsed.add([lng.toDouble(), lat.toDouble()]);
    }

    if (parsed.length < 2) return null; // need at least 2 points to draw a line
    return parsed;
  }

  // ─── GPS TRACKING ─────────────────────────────────────────────────────────────

  // _startPositionTracking begins the continuous GPS stream.
  // Every time the user moves at least 3 meters, _updateRouteProgress is called.
  //
  // getPositionStream() returns a Stream<geo.Position> — an ongoing sequence of
  // GPS position values that keeps firing until we cancel it.
  //
  // .listen() subscribes to the stream. It returns a StreamSubscription, which
  // we save in _positionStream so we can cancel it later in dispose().
  void _startPositionTracking() {
    _positionStream?.cancel(); // cancel any previous subscription first

    _positionStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best, // use the most precise GPS available
        distanceFilter: 3, // only emit a new position if the user moved at least 3 meters
                            // this prevents the stream from firing 30 times/second while standing still
      ),
    ).listen(
      _updateRouteProgress, // this function is called for every new GPS position
      onError: (Object error, StackTrace stackTrace) {
        // GPS stream errors are usually recoverable — just log them, don't crash.
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
    _positionStream = null; // clear the reference so it can be garbage collected
  }

  // _updateRouteProgress is called every time the GPS stream fires (user moved ≥ 3 m).
  // This is the core of live navigation — it does three things every GPS update:
  //   1. Filter tiny wobbles (ignore if movement < _minMovementMeters)
  //   2. Trim the route line to only show the remaining path
  //   3. Detect arrival or off-route
  //
  // This is a regular void function (not async) because it is called by the stream
  // listener. Any async work it needs to trigger is "fire and forget" with unawaited().
  void _updateRouteProgress(geo.Position position) {
    // Safety checks — ignore the update if we are not in a state to handle it.
    if (_fullRouteCoords.length < 2 ||    // no route to trim yet
        _mapboxMap == null ||              // map not ready
        _phase == NavigationPhase.loadingRoute || // in the middle of fetching a route
        !_trackingStarted) {              // stream fired before we were ready
      return;
    }

    // --- MINIMUM MOVEMENT FILTER ---
    // GPS hardware "wobbles" — even standing perfectly still the reported position
    // can drift by a meter or two. Without this filter those micro-movements would
    // trigger constant redraws and off-route checks.
    final last = _lastAcceptedPosition; // the last position we actually used
    if (last != null) {
      // distanceBetween() returns the distance in meters between two GPS coordinates.
      final movement = geo.Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );
      if (movement < _minMovementMeters) return; // movement too small, ignore
    }

    _lastAcceptedPosition = position; // remember this as the last accepted position

    // --- FIND CLOSEST ROUTE POINT ---
    // Search the route coordinates list to find which point is nearest to the user.
    // closestIndex = the index into _fullRouteCoords of that nearest point.
    // minDistance  = how many meters off the route line the user currently is.
    //
    // Dart "records" (the (int, double) syntax) let a function return two values
    // at once without creating a separate class. Think of it as an anonymous pair.
    final (closestIndex, minDistance) = _findClosestRoutePoint(position);
    _lastClosestIndex = closestIndex;

    // --- CHECK ARRIVAL ---
    // distanceBetween() calculates the straight-line distance from the user
    // to the exact destination coordinates.
    final distanceToDestination = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      widget.destLat,
      widget.destLng,
    );

    if (distanceToDestination <= _arrivalThresholdMeters) {
      if (_phase != NavigationPhase.arrived) {
        // Stop the GPS stream — we don't need it anymore.
        _stopPositionTracking();
        _trackingStarted = false;
        _setStateIfMounted(() {
          _phase = NavigationPhase.arrived; // triggers the arrival overlay in build()
        });
        _clearStatus();
        AppLogger.info('User arrived at destination', category: 'navigation');
      }
      return; // arrived — nothing else to do
    }

    // --- CHECK OFF-ROUTE ---
    // If the user is more than _offRouteThresholdMeters from the route line,
    // start a reroute. _canRerouteNow() enforces the cooldown so we don't spam the API.
    if (minDistance > _offRouteThresholdMeters) {
      if (_canRerouteNow()) {
        // unawaited() is how you "fire and forget" an async function from a sync context.
        // We can't use await here because _updateRouteProgress is not async.
        // The reroute runs in the background; this function returns immediately.
        unawaited(_rerouteFromPosition(position, minDistance));
      }
      return;
    }

    // --- TRIM THE ROUTE LINE ---
    // sublist(closestIndex) returns a NEW list starting at closestIndex.
    // Everything before closestIndex is behind the user — we discard it.
    // This is what makes the blue line "shrink" as the user walks.
    final remainingRoute = _fullRouteCoords.sublist(closestIndex);
    unawaited(_updateMapWithCoords(remainingRoute)); // update the map in the background
  }

  // _findClosestRoutePoint scans the route coordinates and returns the index of the
  // point closest to the current GPS position, plus the distance to that point.
  //
  // (int, double) is a Dart "record" — a lightweight way to return two values.
  // The caller unpacks it like: final (index, distance) = _findClosestRoutePoint(pos);
  (int, double) _findClosestRoutePoint(geo.Position position) {
    double minDistance = double.infinity; // start with "infinite" — any real distance is smaller
    int closestIndex = _lastClosestIndex;

    // Optimization: only scan from a bit behind the last known position.
    // We don't need to check the whole route — the user can't teleport backwards.
    // clamp(0, max) makes sure we never go below index 0 (no negative indices).
    final startIndex = (_lastClosestIndex - 8).clamp(
      0,
      _fullRouteCoords.length - 1,
    );

    for (int i = startIndex; i < _fullRouteCoords.length; i++) {
      final coord = _fullRouteCoords[i];
      // IMPORTANT: Mapbox stores coordinates as [longitude, latitude].
      // Geolocator.distanceBetween expects (lat1, lng1, lat2, lng2).
      // So coord[1] = latitude, coord[0] = longitude.
      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        coord[1], // latitude (index 1 in the [lng, lat] pair)
        coord[0], // longitude (index 0)
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i; // this index is now the closest we've found
      }
    }

    return (closestIndex, minDistance); // return both values as a record
  }

  // _canRerouteNow checks whether the cooldown has passed since the last reroute.
  // Returns true if we are allowed to reroute right now.
  bool _canRerouteNow() {
    if (!_trackingStarted) return false;               // can't reroute before tracking starts
    if (_phase == NavigationPhase.rerouting) return false; // already mid-reroute
    if (_lastRerouteAt == null) return true;           // first ever reroute — always allowed
    // DateTime.now().difference(_lastRerouteAt!) = how long since last reroute
    // >= _rerouteCooldown = at least 20 seconds have passed
    return DateTime.now().difference(_lastRerouteAt!) >= _rerouteCooldown;
  }

  // _rerouteFromPosition calculates a fresh route starting from where the user
  // currently is. Called when the off-route check fires.
  Future<void> _rerouteFromPosition(
    geo.Position position,
    double offRouteMeters,
  ) async {
    _setStateIfMounted(() {
      _phase = NavigationPhase.rerouting;
    });
    _lastRerouteAt = DateTime.now(); // record the time so the cooldown starts now

    _setStatus(
      'You seem off route (~${offRouteMeters.toStringAsFixed(0)}m). Recalculating...',
      // .toStringAsFixed(0) rounds the double to 0 decimal places: 42.7 → "43"
    );

    AppLogger.warning(
      'Off-route detected at ${offRouteMeters.toStringAsFixed(1)}m; rerouting',
      category: 'navigation',
    );

    // Fetch a new route starting from the user's current position.
    // useDeviceLocation: false because we already have the position — no need to re-read GPS.
    // forcedStart: position — use exactly where the user is right now as the route start.
    final rerouted = await _recalculateRoute(
      useDeviceLocation: false,
      forcedStart: position,
    );

    _setStateIfMounted(() {
      _phase = NavigationPhase.tracking; // resume tracking regardless of result
    });
    if (rerouted) {
      _clearStatus(); // new route is ready — hide the "Recalculating..." message
    } else {
      _setStatus(
        'Could not refresh the route right now. Keeping your current path.',
        actions: {NavigationStatusAction.retry},
      );
    }
  }

  // _updateMapWithCoords pushes a list of coordinates into the Mapbox source.
  // Mapbox automatically redraws the line layer whenever the source data changes.
  //
  // coords = [] means "erase the line" (empty FeatureCollection).
  // coords with 2+ points draws the blue route line.
  Future<void> _updateMapWithCoords(List<List<double>> coords) async {
    if (_mapboxMap == null || !_styleArtifactsReady) return;

    // GeoJSON LineString requires at least 2 points.
    // If we only have 1 (very near the destination), duplicate it to satisfy the spec.
    final normalizedCoords = coords.length == 1
        ? [coords.first, coords.first] // [A] → [A, A]
        : coords;

    // Build the GeoJSON string that Mapbox will use to redraw the line.
    // json.encode() converts a Dart Map/List → a JSON string.
    // An empty coords list gets an empty FeatureCollection (clears the line).
    final routeGeoJson = coords.isEmpty
        ? '{"type":"FeatureCollection","features":[]}'
        : json.encode({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'properties': {}, // required by GeoJSON spec even if empty
                'geometry': {
                  'type': 'LineString',
                  'coordinates': normalizedCoords, // the list of [lng, lat] points
                },
              },
            ],
          });

    try {
      // Update ONLY the "data" property of the source.
      // This is cheaper than removing and re-adding the whole source/layer.
      // Mapbox sees the data change and redraws the layer immediately.
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

  void _chooseIcon() async { //function to toggle between images/icons
    if (_mapboxMap == null) return; // Safety check: don't do anything if the Mapbox map hasn't been initialized yet

    setState(() {
      _currentIcon = _currentIcon == "assets/pic1a.png"
          ? "assets/pic1b.png"
          : "assets/pic1a.png"; // otherwise, switch back to OG
    });

    // Load the selected image file from the app's assets
    final ByteData bytes = await rootBundle.load(_currentIcon);

    // Convert the loaded image to a Uint8List, which Mapbox requires (MUST)
    final Uint8List imageData = bytes.buffer.asUint8List();

    _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true, // ensure the location puck is visible
        puckBearingEnabled: true, // make the puck rotate with device heading
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(
            topImage: imageData, // set the top image of the puck to our selected icon (note that there are shadow images too, hence top for this image)
          ),
        ),
      ),
    );
  }

  // ─── STATUS HELPERS ───────────────────────────────────────────────────────────

  // Called when the user taps the Retry button — runs the full flow again.
  Future<void> _onRetryPressed() async {
    await _startNavigationFlow();
  }

  // Opens the phone's App Settings page for this app.
  // The user can re-enable location permission there.
  Future<void> _openAppSettings() async {
    await geo.Geolocator.openAppSettings();
  }

  // Opens the phone's Location Services settings.
  // The user can turn on GPS there.
  Future<void> _openLocationSettings() async {
    await geo.Geolocator.openLocationSettings();
  }

  // _setStatus updates the status message and action buttons, then rebuilds the UI.
  // We always use _setStateIfMounted() instead of raw setState() to avoid
  // calling setState on a widget that has already been removed from the screen.
  void _setStatus(String message, {Set<NavigationStatusAction> actions = const {}}) {
    _setStateIfMounted(() {
      _statusMessage = message;
      _actions = actions;
    });
  }

  // _clearStatus hides the status card by setting the message back to null.
  void _clearStatus() {
    _setStateIfMounted(() {
      _statusMessage = null;
      _actions = const {};
    });
  }

  // _setStateIfMounted is a safe wrapper around setState().
  //
  // "mounted" is a property every State object has.
  //   mounted = true  → the widget is visible on screen; setState is safe.
  //   mounted = false → the user navigated away; the widget is gone from the tree.
  //
  // Calling setState when mounted = false throws an exception.
  // Using this wrapper everywhere means we never have to remember to check manually.
  //
  // VoidCallback = a function type that takes no arguments and returns nothing.
  // fn is the function we want to run inside setState.
  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return; // bail out if the widget is gone
    setState(fn);
  }

  // ─── UI BUILDERS ──────────────────────────────────────────────────────────────
  //
  // These methods build parts of the widget tree. Keeping them separate from
  // build() makes the code easier to read — build() stays short and high-level.

  // _buildStatusCard builds the card shown at the bottom of the screen during
  // loading or when there is an error message.
  //
  // Positioned inside a Stack places the card at a specific position.
  // left/right/bottom tell it where to sit relative to the Stack edges.
  Widget _buildStatusCard() {
    // Determine if we should show a loading spinner at the top of the card.
    // A spinner is appropriate while waiting for something — not on a static error.
    final showSpinner =
        _phase == NavigationPhase.initializing ||
        _phase == NavigationPhase.loadingRoute ||
        _phase == NavigationPhase.rerouting;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16, // 16 pixels above the bottom of the screen
      child: Card(
        // withValues(alpha: 0.96) = 96% opaque (slightly see-through).
        // The map is visible underneath, giving a layered feel.
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        elevation: 6, // shadow depth
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // left-align children
            children: [

              // Thin animated progress bar while loading.
              // LinearProgressIndicator with no value = indeterminate (keeps animating).
              if (showSpinner)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 4),
                ),

              // The status/error message text. Only shown if _statusMessage is not null.
              if (_statusMessage != null)
                Text(_statusMessage!, style: const TextStyle(fontSize: 13.5)),
                // _statusMessage! = the ! tells Dart "I know this is not null here"
                // We already checked (if _statusMessage != null) so this is safe.

              // Action buttons — only shown if there are any.
              // Wrap lays out children left-to-right and wraps to a new line if needed.
              if (_actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,    // horizontal space between buttons
                    runSpacing: 6, // vertical space between wrapped rows
                    children: [
                      // Each button is only added to the list if its action is in _actions.
                      // .contains() checks membership in the Set.
                      if (_actions.contains(NavigationStatusAction.retry))
                        OutlinedButton.icon(
                          onPressed: _onRetryPressed,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                      if (_actions.contains(NavigationStatusAction.openAppSettings))
                        OutlinedButton.icon(
                          onPressed: _openAppSettings,
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('App Settings'),
                        ),
                      if (_actions.contains(NavigationStatusAction.openLocationSettings))
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

  // _buildArrivalOverlay is the full-screen "You have arrived!" card shown
  // when the user gets within _arrivalThresholdMeters of the destination.
  //
  // Positioned.fill makes it cover the entire Stack (all four edges).
  // The semi-transparent black background dims the map to draw attention to the card.
  Widget _buildArrivalOverlay() {
    return Positioned.fill(
      child: Container(
        // withValues(alpha: 0.5) = 50% black overlay (dims the map behind it).
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
                // mainAxisSize.min = card shrinks to exactly fit its content.
                // Without this the card would stretch to fill the full screen height.
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 72),
                  const SizedBox(height: 16),

                  // Show the event name so the user knows which event they reached.
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

                  // "Done" button pops this screen off the Navigator stack —
                  // the user goes back to wherever they came from (EventDetailScreen).
                  SizedBox(
                    width: double.infinity, // stretch button to card width
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
