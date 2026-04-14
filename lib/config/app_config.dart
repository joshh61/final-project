// AppConfig holds values that are passed into the app at run time.
// Instead of hardcoding secret keys directly in code (which is a security risk),
// we read them from the environment using String.fromEnvironment / bool.fromEnvironment.
//
// How to pass a value when running the app:
//   flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.abc123...
//
// If no value is passed, the defaultValue is used instead.

class AppConfig {
  // Private constructor — this class is never instantiated.
  // The underscore makes it private (only usable inside this file).
  // We only ever call AppConfig.mapboxAccessToken, never AppConfig().
  AppConfig._();

  // The Mapbox token needed to load map tiles and call the Directions API.
  // String.fromEnvironment reads from --dart-define at compile time.
  // defaultValue is the hardcoded token so the app works without --dart-define.
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue:
        'pk.eyJ1IjoidXRlcG1pbmVyejI1NTIiLCJhIjoiY21sdmcxYWcyMDg5bDNocG82a2N5MmF6biJ9.Pd77daI-yM4ryGhS8G0mlQ',
  );

  // When true, shows extra developer information in the navigation screen.
  // Defaults to false so normal users never see debug info.
  static const bool enableDevTools = bool.fromEnvironment(
    'ENABLE_DEV_TOOLS',
    defaultValue: false,
  );

  // When true, prints extra log messages to the debug console.
  // Useful during development to trace what the app is doing.
  static const bool enableVerboseLogs = bool.fromEnvironment(
    'ENABLE_VERBOSE_LOGS',
    defaultValue: false,
  );
}
