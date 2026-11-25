/// Replacement for the ~94 raw `print()` calls scattered through the app.
///
/// Uses `dart:developer`'s [log] so output is attributed to a name, is
/// filterable in DevTools, and is stripped from release builds (unlike
/// `print`, which ships and costs frames).
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class Log {
  /// Master switch. Release builds only surface warnings and errors.
  static bool verbose = kDebugMode;

  static void d(String tag, Object? message) =>
      _write(LogLevel.debug, tag, message);

  static void i(String tag, Object? message) =>
      _write(LogLevel.info, tag, message);

  static void w(String tag, Object? message, [Object? error]) =>
      _write(LogLevel.warn, tag, message, error);

  static void e(String tag, Object? message, [Object? error, StackTrace? st]) =>
      _write(LogLevel.error, tag, message, error, st);

  static void _write(
    LogLevel level,
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!verbose && level.index < LogLevel.warn.index) return;

    // Never let logging throw into app code.
    try {
      developer.log(
        message?.toString() ?? 'null',
        name: tag,
        level: switch (level) {
          LogLevel.debug => 500,
          LogLevel.info => 800,
          LogLevel.warn => 900,
          LogLevel.error => 1000,
        },
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }
}
