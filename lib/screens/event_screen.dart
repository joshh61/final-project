import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/event_category.dart';
import '../services/firestore_service.dart';
import 'event_detail_screen.dart';

enum _DateFilter { today, thisWeek, thisMonth, custom }

// Events with at least this many hypes appear in the "Popular" section.
const int _popularThreshold = 1;

// ─── EventsScreen ─────────────────────────────────────────────────────────────
// StatefulWidget so we can manage two live Firestore streams:
//   1. All events (for the main list)
//   2. The current user's saved event IDs (for the Favorites section + card icons)

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  List<Event> _allEvents = [];
  // A Set gives O(1) lookup — checking if an event is saved is just .contains()
  Set<String> _savedEventIds = {};
  bool _loading = true;

  // null = show all categories; non-null = show only that category.
  EventCategory? _selectedCategory;

  // null = show all dates; non-null = apply a date filter.
  _DateFilter? _selectedDateFilter;
  DateTimeRange? _customDateRange;

  // We keep these subscriptions so we can cancel them in dispose().
  // Forgetting to cancel causes memory leaks and "setState on disposed widget" errors.
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<Set<String>>? _savedSubscription;

  @override
  void initState() {
    super.initState();

    // Subscribe to the events collection — fires every time any event changes.
    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      // Sort by hypeCount so most-hyped events appear first.
      events.sort((a, b) => b.hypeCount.compareTo(a.hypeCount));
      setState(() {
        _allEvents = events;
        _loading = false;
      });
    });

    // Subscribe to the user's saved event IDs — fires when they save/unsave.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _savedSubscription =
          _firestoreService.getSavedEventIdsStream(uid).listen((ids) {
        setState(() => _savedEventIds = ids);
      });
    }
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _savedSubscription?.cancel();
    super.dispose();
  }

  // Called when the user taps the bookmark icon on a card or detail screen.
  // The stream will fire shortly after and rebuild the list with the new state.
  Future<void> _toggleSave(Event event) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || event.id == null) return;

    if (_savedEventIds.contains(event.id)) {
      await _firestoreService.unsaveEvent(uid, event.id!);
    } else {
      await _firestoreService.saveEvent(uid, event);
    }
  }

  // Uses eventDate if set, otherwise falls back to createdAt.
  // This way old events still participate in date filtering.
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

  Future<void> _pickCustomRange(BuildContext context) async {
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
    }
  }

  Widget _dateChip(
      BuildContext context, String label, _DateFilter filter, IconData icon) {
    final selected = _selectedDateFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(icon, size: 14, color: selected ? Colors.white : Colors.grey),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _selectedDateFilter = selected ? null : filter;
          _customDateRange = null;
        }),
        selectedColor: Colors.orange,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontSize: 12,
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildDateFilter(BuildContext context) {
    final customLabel =
        _selectedDateFilter == _DateFilter.custom && _customDateRange != null
            ? '${DateFormat('MMM d').format(_customDateRange!.start)} – '
                '${DateFormat('MMM d').format(_customDateRange!.end)}'
            : 'Custom Range';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('All Dates'),
                selected: _selectedDateFilter == null,
                onSelected: (_) => setState(() {
                  _selectedDateFilter = null;
                  _customDateRange = null;
                }),
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: _selectedDateFilter == null
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                showCheckmark: false,
              ),
            ),
            _dateChip(context, 'Today', _DateFilter.today, Icons.today),
            _dateChip(context, 'This Week', _DateFilter.thisWeek,
                Icons.view_week),
            _dateChip(context, 'This Month', _DateFilter.thisMonth,
                Icons.calendar_month),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: Icon(Icons.date_range,
                    size: 14,
                    color: _selectedDateFilter == _DateFilter.custom
                        ? Colors.white
                        : Colors.grey),
                label: Text(customLabel),
                selected: _selectedDateFilter == _DateFilter.custom,
                onSelected: (_) => _pickCustomRange(context),
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: _selectedDateFilter == _DateFilter.custom
                      ? Colors.white
                      : Colors.black87,
                  fontSize: 12,
                ),
                showCheckmark: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: const Center(
            child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    if (_allEvents.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No events yet!',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Apply category and date filters — null on either means show all.
    final filtered = _allEvents
        .where((e) =>
            (_selectedCategory == null || e.category == _selectedCategory) &&
            _matchesDateFilter(e))
        .toList();

    // Split filtered events into sections.
    final savedEvents =
        filtered.where((e) => _savedEventIds.contains(e.id)).toList();
    final popular = filtered
        .where((e) => e.hypeCount >= _popularThreshold)
        .toList();
    final regular = filtered
        .where((e) => e.hypeCount < _popularThreshold)
        .toList();

    // Build a flat list of headers + cards for a single scrollable ListView.
    final List<Widget> items = [];

    if (savedEvents.isNotEmpty) {
      items.add(const _SectionHeader(
          icon: Icons.bookmark, label: 'My Favorites'));
      for (final e in savedEvents) {
        items.add(_EventCard(
          event: e,
          isSaved: true,
          onSaveToggled: () => _toggleSave(e),
        ));
      }
    }

    if (popular.isNotEmpty) {
      items.add(const _SectionHeader(
          icon: Icons.local_fire_department, label: 'Popular'));
      for (final e in popular) {
        items.add(_EventCard(
          event: e,
          isSaved: _savedEventIds.contains(e.id),
          onSaveToggled: () => _toggleSave(e),
        ));
      }
    }

    if (regular.isNotEmpty) {
      items.add(_SectionHeader(
          icon: Icons.event,
          label: popular.isEmpty && savedEvents.isEmpty
              ? 'All Events'
              : 'All Events'));
      for (final e in regular) {
        items.add(_EventCard(
          event: e,
          isSaved: _savedEventIds.contains(e.id),
          onSaveToggled: () => _toggleSave(e),
        ));
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryFilter(),
          _buildDateFilter(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: items,
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text(
        'Campus Events',
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      backgroundColor: Colors.orange,
      elevation: 0,
    );
  }

  // Horizontal scrollable row of chips — one "All" chip plus one per category.
  // Tapping a category chip filters the list to that category only.
  // Tapping the same chip again (or "All") resets to show everything.
  Widget _buildCategoryFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "All" chip — selected when no category filter is active.
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('All'),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: _selectedCategory == null
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                showCheckmark: false,
              ),
            ),
            // One chip per EventCategory value.
            ...EventCategory.values.map((cat) {
              final selected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(cat.icon,
                      size: 14, color: selected ? Colors.white : cat.color),
                  label: Text(cat.label),
                  selected: selected,
                  // Tapping the already-selected chip deselects it (back to All).
                  onSelected: (_) => setState(
                      () => _selectedCategory = selected ? null : cat),
                  selectedColor: cat.color,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                  showCheckmark: false,
                  side: BorderSide(color: cat.color, width: 1.5),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Event card ───────────────────────────────────────────────────────────────

class _EventCard extends StatefulWidget {
  final Event event;
  final bool isSaved;
  final VoidCallback onSaveToggled;

  const _EventCard({
    required this.event,
    required this.isSaved,
    required this.onSaveToggled,
  });

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  final FirestoreService _firestoreService = FirestoreService();

  // Local hype state — updates instantly on tap.
  late bool _hasHyped;
  late int _hypeCount;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _hasHyped = uid != null && widget.event.hypedBy.contains(uid);
    _hypeCount = widget.event.hypeCount;
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  Widget _priceBadge(bool isFree) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isFree
            ? Colors.green.shade600.withValues(alpha: 0.92)
            : Colors.red.shade600.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFree ? Icons.money_off : Icons.attach_money,
            color: Colors.white,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            isFree ? 'FREE' : 'PAID',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onHypeTapped() async {
    final uid = _currentUid;
    if (uid == null) return;

    final wasHyped = _hasHyped;
    setState(() {
      _hasHyped = !wasHyped;
      _hypeCount += wasHyped ? -1 : 1;
    });

    try {
      if (wasHyped) {
        await _firestoreService.unhypeEvent(widget.event.id!, uid);
      } else {
        await _firestoreService.hypeEvent(widget.event.id!, uid);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasHyped = wasHyped;
          _hypeCount += wasHyped ? 1 : -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: widget.event),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Orange header banner with bookmark ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                  left: 16, top: 12, bottom: 12, right: 4),
              decoration: const BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.event.name.isNotEmpty
                          ? widget.event.name
                          : 'Unnamed Event',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Bookmark button — tapping here does NOT navigate to detail
                  // because IconButton handles its own tap before the parent
                  // GestureDetector can see it.
                  IconButton(
                    icon: Icon(
                      widget.isSaved
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: widget.onSaveToggled,
                    tooltip: widget.isSaved ? 'Remove from favorites' : 'Save to favorites',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Event photo ─────────────────────────────────────────────────
            if (widget.event.imageUrl != null)
              CachedNetworkImage(
                imageUrl: widget.event.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => const SizedBox(
                  height: 160,
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.orange)),
                ),
                errorWidget: (context, url, error) => const SizedBox(
                  height: 60,
                  child: Center(
                      child: Icon(Icons.broken_image, color: Colors.grey)),
                ),
              ),

            // ── Event details ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.description.isNotEmpty
                        ? widget.event.description
                        : 'No description available.',
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black87, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  // Category pill badge — mirrors the style on EventDetailScreen.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.event.category.color
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: widget.event.category.color
                              .withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.event.category.icon,
                            size: 11,
                            color: widget.event.category.color),
                        const SizedBox(width: 4),
                        Text(
                          widget.event.category.label,
                          style: TextStyle(
                            color: widget.event.category.color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.event.latitude.toStringAsFixed(4)}, ${widget.event.longitude.toStringAsFixed(4)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),

                      // Star rating badge
                      if (widget.event.reviewCount > 0)
                        Row(
                          children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              widget.event.averageRating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),

                      // RSVP count badge
                      if (widget.event.rsvpCount > 0)
                        Row(
                          children: [
                            const Icon(Icons.people,
                                color: Colors.green, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.event.rsvpCount}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),

                      // Free / Paid badge
                      _priceBadge(widget.event.isFree),
                      const SizedBox(width: 8),

                      // Hype button
                      GestureDetector(
                        onTap: _onHypeTapped,
                        behavior: HitTestBehavior.opaque,
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(_hasHyped),
                          tween: Tween(begin: 1.3, end: 1.0),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _hasHyped
                                      ? Icons.local_fire_department
                                      : Icons.local_fire_department_outlined,
                                  key: ValueKey(_hasHyped),
                                  color: _hasHyped
                                      ? Colors.orange
                                      : Colors.grey,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 3),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) =>
                                    SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.5),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: FadeTransition(
                                      opacity: animation, child: child),
                                ),
                                child: Text(
                                  '$_hypeCount',
                                  key: ValueKey(_hypeCount),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _hasHyped
                                        ? Colors.orange
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
