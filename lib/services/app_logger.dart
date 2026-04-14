// AppLogger is a structured logging helper.
// Instead of calling print() everywhere (which shows up even in the App Store build),
// we use this class so debug messages are automatically hidden in release builds.
//
// Usage:
//   AppLogger.info('Map created', category: 'navigation');
//   AppLogger.warning('GPS failed', category: 'permission', error: e);
//   AppLogger.error('Crash!', category: 'network', error: e, stackTrace: st);

import 'dart:developer' as developer;
// dart:developer gives us the log() function, which shows in the Flutter DevTools
// log viewer. It is smarter than print() because it supports error and stackTrace.

import 'package:flutter/foundation.dart';
// kDebugMode is true when running a debug build (flutter run), false in release.

class AppLogger {
  // Private constructor — same pattern as AppConfig, never instantiated.
  AppLogger._();

  // Every log line is tagged with this name so you can filter in DevTools.
  static const String _loggerName = 'CampusVibes';

  // DEBUG — very detailed step-by-step tracing. Only prints in debug builds.
  // Use this for "I am now inside function X" style messages.
  static void debug(String message, {String category = 'general'}) {
    if (!kDebugMode) return; // stops here in release builds
    _log('DEBUG', message, category: category);
  }

  // INFO — "this thing happened successfully". Only prints in debug builds.
  // Use this to confirm that major steps completed.
  static void info(String message, {String category = 'general'}) {
    if (!kDebugMode) return;
    _log('INFO', message, category: category);
  }

  // WARNING — something unexpected happened but the app can keep going.
  // Prints in BOTH debug and release builds.
  // error and stackTrace are optional — include them when you have an exception.
  static void warning(
    String message, {
    String category = 'general',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      'WARN',
      message,
      category: category,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // ERROR — something failed and it will affect the user.
  // Prints in BOTH debug and release builds.
  static void error(
    String message, {
    String category = 'general',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      'ERROR',
      message,
      category: category,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Private helper that formats and emits the log line.
  // All public methods call this — it is the single place that touches developer.log().
  static void _log(
    String level,
    String message, {
    required String category,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      '[$level][$category] $message', // e.g. [INFO][navigation] Route loaded
      name: _loggerName,              // appears as the logger tag in DevTools
      error: error,
      stackTrace: stackTrace,
    );
  }
}
