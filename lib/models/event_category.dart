import 'package:flutter/material.dart';

/// Defines the seven possible categories for a campus event.
///
/// Dart 3 "enhanced enums" let you put getters and static methods directly
/// inside the enum body — no separate extension class needed.
enum EventCategory {
  academic,
  social,
  sports,
  clubMeeting,
  careerFair,
  workshop,
  other;

  /// Human-readable label. Also used as the Firestore field value so that
  /// the stored string is readable without a lookup table.
  String get label {
    switch (this) {
      case EventCategory.academic:    return 'Academic';
      case EventCategory.social:      return 'Social';
      case EventCategory.sports:      return 'Sports';
      case EventCategory.clubMeeting: return 'Club Meeting';
      case EventCategory.careerFair:  return 'Career Fair';
      case EventCategory.workshop:    return 'Workshop';
      case EventCategory.other:       return 'Other';
    }
  }

  /// The color used for map circle markers and UI badges.
  /// Each category gets a visually distinct hue so users can tell them apart
  /// at a glance on the map.
  Color get color {
    switch (this) {
      case EventCategory.academic:    return Colors.blue.shade600;
      case EventCategory.social:      return Colors.purple.shade500;
      case EventCategory.sports:      return Colors.green.shade600;
      case EventCategory.clubMeeting: return Colors.teal.shade600;
      case EventCategory.careerFair:  return Colors.orange.shade700;
      case EventCategory.workshop:    return Colors.red.shade400;
      case EventCategory.other:       return Colors.grey.shade600;
    }
  }

  /// Icon used in filter chips and category badges.
  IconData get icon {
    switch (this) {
      case EventCategory.academic:    return Icons.school;
      case EventCategory.social:      return Icons.people;
      case EventCategory.sports:      return Icons.sports_soccer;
      case EventCategory.clubMeeting: return Icons.groups;
      case EventCategory.careerFair:  return Icons.work;
      case EventCategory.workshop:    return Icons.build;
      case EventCategory.other:       return Icons.event;
    }
  }

  /// Deserializes a Firestore string back to an enum value.
  /// Old documents without a 'category' field return null here,
  /// so the null case falls through to EventCategory.other.
  static EventCategory fromString(String? value) {
    switch (value) {
      case 'Academic':    return EventCategory.academic;
      case 'Social':      return EventCategory.social;
      case 'Sports':      return EventCategory.sports;
      case 'Club Meeting': return EventCategory.clubMeeting;
      case 'Career Fair': return EventCategory.careerFair;
      case 'Workshop':    return EventCategory.workshop;
      default:            return EventCategory.other;
    }
  }
}
