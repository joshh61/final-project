import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:final_project/logic/navigation_access_evaluator.dart';
import 'package:final_project/models/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/* without needing the whole app to run. One test checks that event data is
saved in the shape Firestore expects, and the other checks an important
navigation rule when location services are turned off*/

void main() {
  group('simple unit tests', () {
    test('toMap stores the fields Firestore expects', () {
      // Build one Event object with known values.
      final createdAt = DateTime(2026, 4, 25, 10, 30);
      final event = Event(
        name: 'Study Group', //----------------MATCH
        description: 'Meet in the library',
        latitude: 31.77,
        longitude: -106.50,
        createdAt: createdAt,
        hypeCount: 3,
        hypedBy: const ['u1', 'u2', 'u3'],
        rsvpCount: 4,
        averageRating: 4.5,
        reviewCount: 2,
        createdBy: 'organizer-9', //-------------MATCH
      );

      // Convert the Event into the map that would be sent to Firestore.
      final map = event.toMap();

      // Check a few key fields so we know the conversion kept the right data.
      expect(map['name'], 'Study Group'); //--------------------------------------------MATCH
      expect(map['createdBy'], 'organizer-9'); //--------------------------------------------MATCH
      expect((map['createdAt'] as Timestamp).toDate(), createdAt);

      // Firestore stores the document ID separately, so it should not be here.
      expect(map.containsKey('id'), isFalse);
    });

    test('new events start with default values', () { //ensuring new events behave as expected
      final event = Event(
        name: 'Campus Concert',
        description: 'Live music outside',
        latitude: 31.76,
        longitude: -106.48,
        createdBy: 'user-123',
      );

      expect(event.id, isNull);
      expect(event.hypeCount, 0);
      expect(event.hypedBy, isEmpty);
      expect(event.rsvpCount, 0);
    });

    test('blocks live navigation when location services are off', () {
      // Pretend the app has permission, but the phone's location services
      // are still turned off at the system level.
      final decision = NavigationAccessEvaluator.evaluate(
        serviceEnabled: false, //no at the system level
        permission: LocationPermission.whileInUse, //yes at the app level
      );

      // The evaluator should block navigation and guide the user to fix it.
      expect(decision.canUseLiveLocation, isFalse);
      expect(
        decision.message,
        'Turn on Location Services to start live walking directions.',
      );
      expect(
        decision.actions,
        {
          NavigationStatusAction.retry, //   Re-checks the state after user potentially fixes settings
          NavigationStatusAction.openLocationSettings, //   link so the user may manually enable system-level location
        },
      );
    });

    test('allows live navigation when location permission is available', () {
      // This is the happy path where services are on and permission is granted.
      final decision = NavigationAccessEvaluator.evaluate(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
      );

      expect(decision.canUseLiveLocation, isTrue);
      expect(decision.message, isNull);
      expect(decision.actions, isEmpty);
    });
  });
}
