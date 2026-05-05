import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'screens/event_detail_screen.dart';
// Firebase initialization
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
// Firestore service and Event model
import 'package:intl/intl.dart';
import 'services/firestore_service.dart';
import 'models/event.dart';
import 'models/event_category.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum _DateFilter { today, thisWeek, thisMonth, custom }

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
      home: const SplashScreen(),
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
  static const int _maxEventTitleLength = 30;
  static const int _maxEventDescriptionLength = 225;

  bool _isWithinEventCreationBounds(Position coords) {
    //for event creation, technicality (not precise but accurate)
    return coords.lat >= 26.30273 &&
        coords.lat <= 26.31152 &&
        coords.lng >= -98.18600 &&
        coords.lng <= -98.16800;
  }

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

  // IDs for the route source/layer (must be unique in the style).
  static const _routeSourceId = "route-source";
  static const _routeLayerId = "route-layer";

  // Last batch of events from Firestore — cached so the filter dropdown can
  // redraw markers without waiting for the next Firestore stream emission.
  List<Event> _cachedEvents = [];

  // null = show all categories. Non-null = show only that category.
  EventCategory? _selectedMapCategory;

  // null = show all dates. Non-null = apply a date filter.
  _DateFilter? _selectedDateFilter;
  DateTimeRange? _customDateRange;

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
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MapWidget(
            cameraOptions: CameraOptions(
              // Initial camera position over campus
              center: Point(
                coordinates: Position(utrgvCenterLng, utrgvCenterLat),
              ),
              zoom: 15.5,
            ),
            // Called once the MapboxMap object is ready
            onMapCreated: _onMapCreated,
            // Called when the style is fully loaded; you add sources/layers here
            onStyleLoadedListener: _onStyleLoaded,
            // Tap on the map to add a new event marker
            onTapListener: (ctx) {
              final coords = ctx.point.coordinates;
              if (!_isWithinEventCreationBounds(coords)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Events can only be created inside campus event bounds',
                    ),
                  ),
                );
                return;
              }
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
            child: _buildMapFilterBar(context),
          ),
        ],
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

    // Listen to Firestore for real-time event updates.
    // _redrawMarkers caches events even if _circleManager isn't ready yet —
    // _onStyleLoaded will pick them up and draw them once the manager exists.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _redrawMarkers(events);
    });
  }

  DateTime _getFilterDate(Event e) => e.eventDate ?? e.createdAt;

  bool _matchesDateFilter(Event e) {
    if (_selectedDateFilter == null) return true;
    final date = _getFilterDate(e);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_selectedDateFilter!) {
      case _DateFilter.today:
        return DateTime(date.year, date.month, date.day) == today;
      case _DateFilter.thisWeek:
        final weekEnd = today.add(const Duration(days: 7));
        final d = DateTime(date.year, date.month, date.day);
        return !d.isBefore(today) && d.isBefore(weekEnd);
      case _DateFilter.thisMonth:
        return date.year == now.year && date.month == now.month;
      case _DateFilter.custom:
        if (_customDateRange == null) return true;
        final d = DateTime(date.year, date.month, date.day);
        return !d.isBefore(_customDateRange!.start) &&
            !d.isAfter(_customDateRange!.end);
    }
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

    // Apply both category and date filters.
    final visible = events.where(
      (e) =>
          (_selectedMapCategory == null ||
              e.category == _selectedMapCategory) &&
          _matchesDateFilter(e),
    );

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

  // Called when the dropdown selection changes.
  // Updates the filter and immediately redraws markers from the cache.
  void _onCategorySelected(EventCategory? cat) {
    setState(() => _selectedMapCategory = cat);
    _redrawMarkers(_cachedEvents);
  }

  // Builds the filter bar that sits at the top of the map.
  // Wrapped in Material so dropdowns and chips have a proper surface and
  // Flutter's gesture system takes priority over the Mapbox MapWidget below.
  Widget _buildMapFilterBar(BuildContext context) {
    final customLabel =
        _selectedDateFilter == _DateFilter.custom && _customDateRange != null
        ? '${DateFormat('MMM d').format(_customDateRange!.start)} – '
              '${DateFormat('MMM d').format(_customDateRange!.end)}'
        : 'Custom';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Category dropdown ──────────────────────────────────────────
            DropdownButtonHideUnderline(
              child: DropdownButton<EventCategory?>(
                value: _selectedMapCategory,
                isExpanded: true,
                hint: const Row(
                  children: [
                    Icon(Icons.filter_list, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'All Categories',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ],
                ),
                items: [
                  const DropdownMenuItem<EventCategory?>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.event, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Text('All Categories', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  ...EventCategory.values.map((cat) {
                    return DropdownMenuItem<EventCategory?>(
                      value: cat,
                      child: Row(
                        children: [
                          Icon(cat.icon, color: cat.color, size: 16),
                          const SizedBox(width: 8),
                          Text(cat.label, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: _onCategorySelected,
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            // ── Date filter chips ──────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _mapDateChip(null, 'All Dates'),
                  _mapDateChip(_DateFilter.today, 'Today'),
                  _mapDateChip(_DateFilter.thisWeek, 'This Week'),
                  _mapDateChip(_DateFilter.thisMonth, 'This Month'),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(customLabel),
                      selected: _selectedDateFilter == _DateFilter.custom,
                      onSelected: (_) => _pickMapCustomRange(context),
                      selectedColor: Colors.orange,
                      labelStyle: TextStyle(
                        color: _selectedDateFilter == _DateFilter.custom
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 11,
                      ),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapDateChip(_DateFilter? filter, String label) {
    final selected = _selectedDateFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _selectedDateFilter = selected ? null : filter;
            _customDateRange = null;
          });
          _redrawMarkers(_cachedEvents);
        },
        selectedColor: Colors.orange,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontSize: 11,
        ),
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
      ),
    );
  }

  Future<void> _pickMapCustomRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _customDateRange,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.orange),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _selectedDateFilter = _DateFilter.custom;
        _customDateRange = range;
      });
      _redrawMarkers(_cachedEvents);
    }
  }

  // Called when the style is fully loaded. Annotation managers must be created
  // here (not in _onMapCreated) because Mapbox wipes them on every style reload.
  Future<void> _onStyleLoaded(StyleLoadedEventData eventData) async {
    if (_mapboxMap == null) return;

    await _mapboxMap!.style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        data: '{"type":"FeatureCollection","features":[]}',
      ),
    );

    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: Colors.blue.toARGB32(),
        lineWidth: 4.0,
      ),
    );

    // Create (or recreate) the circle annotation manager here instead of
    // in _onMapCreated. On iOS, Mapbox wipes annotation managers whenever the
    // style reloads — which happens on pan, zoom, and tab switches. Recreating
    // here guarantees the manager is always fresh after any style load.
    _circleManager = await _mapboxMap!.annotations
        .createCircleAnnotationManager();

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

    // 4) If Firestore already fired before the style finished loading, the
    // events are sitting in _cachedEvents. Redraw them now with whatever
    // filter the user has selected so nothing is lost.
    if (_cachedEvents.isNotEmpty) {
      await _redrawMarkers(_cachedEvents);
    }
  }

  // Dialog to add a new event marker at the tapped coordinates
  Future<void> _showAddDialog(Position coords) async {
    String name = '';
    String desc = '';
    image_picker.XFile? pickedImage;
    bool isFree = true;
    EventCategory category = EventCategory.other;
    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    String? dateError;
    String? startTimeError;
    String? endTimeError;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "New Event",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Event Name",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) => name = val,
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) => desc = val,
                ),
                const SizedBox(height: 12),
                // ── Date ────────────────────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.calendar_today,
                    color: dateError != null ? Colors.red : Colors.orange,
                  ),
                  title: Text(
                    selectedDate == null
                        ? 'Event Date *'
                        : DateFormat('MMM d, yyyy').format(selectedDate!),
                    style: TextStyle(
                      fontSize: 14,
                      color: selectedDate == null
                          ? (dateError != null ? Colors.red : Colors.grey)
                          : Colors.black87,
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (context, child) => Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.orange,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                        dateError = null;
                      });
                    }
                  },
                ),
                if (dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      dateError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                // ── Start time ───────────────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.access_time,
                    color: startTimeError != null ? Colors.red : Colors.orange,
                  ),
                  title: Text(
                    startTime == null
                        ? 'Start Time *'
                        : startTime!.format(context),
                    style: TextStyle(
                      fontSize: 14,
                      color: startTime == null
                          ? (startTimeError != null ? Colors.red : Colors.grey)
                          : Colors.black87,
                    ),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: startTime ?? TimeOfDay.now(),
                      builder: (context, child) => Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.orange,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        startTime = picked;
                        startTimeError = null;
                      });
                    }
                  },
                ),
                if (startTimeError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      startTimeError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                // ── End time ─────────────────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.access_time_filled,
                    color: endTimeError != null ? Colors.red : Colors.orange,
                  ),
                  title: Text(
                    endTime == null ? 'End Time *' : endTime!.format(context),
                    style: TextStyle(
                      fontSize: 14,
                      color: endTime == null
                          ? (endTimeError != null ? Colors.red : Colors.grey)
                          : Colors.black87,
                    ),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          endTime ??
                          (startTime != null
                              ? TimeOfDay(
                                  hour: (startTime!.hour + 1) % 24,
                                  minute: startTime!.minute,
                                )
                              : TimeOfDay.now()),
                      builder: (context, child) => Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.orange,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        endTime = picked;
                        endTimeError = null;
                      });
                    }
                  },
                ),
                if (endTimeError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      endTimeError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 4),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
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
                              Text(
                                cat.label,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(
                        () => category = val ?? EventCategory.other,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      isFree ? 'Free Event' : 'Paid Event',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isFree
                            ? Colors.green.shade700
                            : Colors.red.shade700,
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
                const SizedBox(height: 6),
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
                      final image = await image_picker.ImagePicker().pickImage(
                        source: image_picker.ImageSource.gallery,
                        imageQuality: 80,
                      );
                      if (image != null) {
                        setDialogState(() => pickedImage = image);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final trimmedName = name.trim();
                        final trimmedDesc = desc.trim();

                        if (trimmedName.isEmpty || trimmedDesc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Title and description cannot be empty',
                              ),
                            ),
                          );
                          return;
                        }

                        if (trimmedName.length > _maxEventTitleLength) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Title must be $_maxEventTitleLength characters or less',
                              ),
                            ),
                          );
                          return;
                        }

                        if (trimmedDesc.length > _maxEventDescriptionLength) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Description must be $_maxEventDescriptionLength characters or less',
                              ),
                            ),
                          );
                          return;
                        }

                        bool hasError = false;
                        if (selectedDate == null) {
                          setDialogState(() => dateError = 'Required');
                          hasError = true;
                        }
                        if (startTime == null) {
                          setDialogState(() => startTimeError = 'Required');
                          hasError = true;
                        }
                        if (endTime == null) {
                          setDialogState(() => endTimeError = 'Required');
                          hasError = true;
                        }
                        if (hasError) return;
                        final eventStart = DateTime(
                          selectedDate!.year,
                          selectedDate!.month,
                          selectedDate!.day,
                          startTime!.hour,
                          startTime!.minute,
                        );
                        final eventEnd = DateTime(
                          selectedDate!.year,
                          selectedDate!.month,
                          selectedDate!.day,
                          endTime!.hour,
                          endTime!.minute,
                        );
                        Navigator.pop(context);
                        _saveEvent(
                          coords,
                          trimmedName,
                          trimmedDesc,
                          pickedImage,
                          isFree,
                          category,
                          eventStart,
                          eventEnd,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Add"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Save event to Firestore. The stream listener will automatically
  // pick up the new event and draw it on the map.
  Future<void> _saveEvent(
    Position coords,
    String name,
    String desc,
    image_picker.XFile? imageFile,
    bool isFree,
    EventCategory category,
    DateTime? eventDate,
    DateTime? eventEndDate,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('createdBy', isEqualTo: uid)
          .get();

      if (snapshot.docs.length >= 3) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can only create 3 events")),
        );
        return;
      }
    }

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
      eventDate: eventDate,
      eventEndDate: eventEndDate,
      createdBy: uid,
    );
    await _firestoreService.addEvent(event);
  }
}
