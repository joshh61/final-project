import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/firestore_service.dart';
import 'event_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<List<Event>>? _eventsSubscription;

  // Keyed by midnight of each day for reliable equality checks.
  Map<DateTime, List<Event>> _eventsByDay = {};

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();

    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      final Map<DateTime, List<Event>> grouped = {};
      for (final event in events) {
        // Use eventDate (when the event takes place) if set, otherwise
        // fall back to createdAt. Normalize to midnight so keys always match.
        final source = event.eventDate ?? event.createdAt;
        final day = DateTime(source.year, source.month, source.day);
        grouped.putIfAbsent(day, () => []).add(event);
      }
      setState(() => _eventsByDay = grouped);
    });
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  List<Event> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _eventsByDay[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _getEventsForDay(_selectedDay);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Calendar',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Calendar widget ─────────────────────────────────────────────────
          Container(
            color: Colors.white,
            child: TableCalendar<Event>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: _getEventsForDay,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarStyle: CalendarStyle(
                // Dot marker under days that have events.
                markerDecoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                // Selected day circle.
                selectedDecoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                // Today shown with a lighter tint so it doesn't clash with selected.
                todayDecoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // ── Selected-day label ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat('MMMM d, yyyy').format(_selectedDay),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ),

          // ── Event list for selected day ─────────────────────────────────────
          Expanded(
            child: selectedEvents.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No events on this day',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: selectedEvents.length,
                    itemBuilder: (context, index) {
                      final event = selectedEvents[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: const CircleAvatar(
                            backgroundColor: Colors.orange,
                            child:
                                Icon(Icons.event, color: Colors.white, size: 20),
                          ),
                          title: Text(
                            event.name.isNotEmpty ? event.name : 'Unnamed Event',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: event.description.isNotEmpty
                              ? Text(
                                  event.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.black54),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Hype count badge
                              if (event.hypeCount > 0) ...[
                                const Icon(Icons.local_fire_department,
                                    color: Colors.orange, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  '${event.hypeCount}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(event: event),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
