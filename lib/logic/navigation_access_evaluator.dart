// NavigationAccessEvaluator figures out whether the app is allowed to use GPS.
//
// Before we can show live walking directions we need two things:
//   1. Location services must be turned ON in the phone's Settings.
//   2. The user must have GRANTED location permission to this app.
//
// This class checks both and returns a decision object that tells the
// navigation screen exactly what to do next (show an error, open Settings, retry, etc.).

import 'package:geolocator/geolocator.dart' as geo;
// geolocator gives us LocationPermission and Geolocator.checkPermission().

import '../config/app_config.dart';

// ─── Action enum ──────────────────────────────────────────────────────────────
// An enum is a fixed list of named values.
// NavigationStatusAction describes buttons we can show the user when something
// goes wrong — retry, go to App Settings, or go to Location Settings.
enum NavigationStatusAction { retry, openAppSettings, openLocationSettings }

// ─── Decision data class ──────────────────────────────────────────────────────
// A "data class" is just a class used to carry data — no logic inside it.
// NavigationAccessDecision bundles three things together so we can return
// all of them from a single function call.
class NavigationAccessDecision {
  // true  → GPS is available and we can start live navigation
  // false → something is wrong and we need to show the user a message
  final bool canUseLiveLocation;

  // The message to show the user when canUseLiveLocation is false.
  // null when everything is fine (no message needed).
  final String? message;

  // Which buttons to show alongside the message (retry, open settings, etc.)
  // An empty Set means no buttons.
  final Set<NavigationStatusAction> actions;

  // const constructor — all fields are final (immutable once created)
  const NavigationAccessDecision({
    required this.canUseLiveLocation,
    this.message,
    this.actions = const <NavigationStatusAction>{},
  });
}

// ─── Evaluator ────────────────────────────────────────────────────────────────
class NavigationAccessEvaluator {
  // evaluate() is the main function.
  // It receives the current permission state and returns a decision.
  //
  // We pass these in as parameters (instead of reading them inside the function)
  // so the function is easy to test — we can fake any permission state in a test.
  static NavigationAccessDecision evaluate({
    required bool serviceEnabled,          // is Location turned on in phone Settings?
    required geo.LocationPermission permission, // what permission did the user grant?
  }) {
    // Check 1: Location services completely disabled at the system level.
    // This is different from the app permission — the user has turned off ALL location
    // for the whole phone, not just for this app.
    if (!serviceEnabled) {
      return const NavigationAccessDecision(
        canUseLiveLocation: false,
        message: 'Turn on Location Services to start live walking directions.',
        actions: {
          NavigationStatusAction.retry,
          NavigationStatusAction.openLocationSettings, // send user to phone Settings
        },
      );
    }

    // Check 2: What permission did the user grant this specific app?
    // switch/case is like a series of if/else but cleaner for enum values.
    switch (permission) {
      // "always" = GPS works even when the app is in the background
      // "whileInUse" = GPS works while the app is open — this is what we need
      case geo.LocationPermission.always:
      case geo.LocationPermission.whileInUse:
        // All good — return true with no message
        return const NavigationAccessDecision(canUseLiveLocation: true);

      // User tapped "Deny" on the permission dialog but can still be asked again
      case geo.LocationPermission.denied:
        return const NavigationAccessDecision(
          canUseLiveLocation: false,
          message: 'Allow location access to start live walking directions.',
          actions: {
            NavigationStatusAction.retry,
            NavigationStatusAction.openAppSettings,
          },
        );

      // User tapped "Never ask again" — we can no longer show the dialog.
      // Only App Settings can fix this now.
      case geo.LocationPermission.deniedForever:
        return const NavigationAccessDecision(
          canUseLiveLocation: false,
          message:
              'Location access is blocked. Open app settings to enable live walking directions.',
          actions: {
            NavigationStatusAction.retry,
            NavigationStatusAction.openAppSettings,
          },
        );

      // Rare edge case — the platform could not determine the permission status
      case geo.LocationPermission.unableToDetermine:
        return const NavigationAccessDecision(
          canUseLiveLocation: false,
          message:
              'Unable to determine location access right now. Retry in a moment.',
          actions: {
            NavigationStatusAction.retry,
            NavigationStatusAction.openAppSettings,
          },
        );
    }
  }

  // locationReadFailureMessage() returns the right error text when GPS fails to
  // return a position. In dev mode it says "GPS hasn't settled" (helpful hint).
  // In normal mode it gives a clean user-facing message.
  static String locationReadFailureMessage() {
    if (AppConfig.enableDevTools) {
      return 'GPS has not settled yet. Using the campus fallback start for debugging.';
    }
    return 'Could not read your current location yet. Retry after GPS settles.';
  }
}
