/// Central error type for the whole app.
///
/// The old code did `catch (_) { return null; }` everywhere, which made
/// "network is down", "we are rate limited", and "this movie has no episodes"
/// indistinguishable to the UI. Every data-layer failure should now throw an
/// [AppError] with a [kind] so screens can render one honest message and one
/// retry button.
library;

import 'dart:async';
import 'dart:io';

enum AppErrorKind {
  /// No interface / DNS failure / socket refused.
  offline,

  /// Took longer than the deadline.
  timeout,

  /// 401/403 — credentials missing or wrong.
  unauthorized,

  /// 404 or empty payload for a valid request.
  notFound,

  /// 429 or TMDB/AniList throttling.
  rateLimited,

  /// 5xx or a provider that is sleeping/suspended.
  serverError,

  /// Response arrived but did not look like what we expected.
  parse,

  /// We were asked to do something invalid (bad config, bad URL, bad id).
  badRequest,

  /// Anything else.
  unknown,
}

class AppError implements Exception {
  final AppErrorKind kind;
  final String message;

  /// Underlying error, kept for logging only. Never shown to users.
  final Object? cause;

  const AppError(this.kind, this.message, {this.cause});

  /// Maps a raw exception from dart:io / http into an [AppError].
  factory AppError.from(Object error, {String? context}) {
    final prefix = context == null ? '' : '$context: ';
    if (error is AppError) return error;
    if (error is TimeoutException) {
      return AppError(
        AppErrorKind.timeout,
        '${prefix}The server took too long to answer.',
        cause: error,
      );
    }
    if (error is SocketException) {
      return AppError(
        AppErrorKind.offline,
        '${prefix}You appear to be offline.',
        cause: error,
      );
    }
    if (error is FormatException) {
      return AppError(
        AppErrorKind.parse,
        '${prefix}The server sent something unreadable.',
        cause: error,
      );
    }
    return AppError(
      AppErrorKind.unknown,
      '${prefix}Something went wrong.',
      cause: error,
    );
  }

  /// Maps an HTTP status code to a kind. Returns null for 2xx.
  static AppErrorKind? kindForStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return null;
    if (statusCode == 401 || statusCode == 403) {
      return AppErrorKind.unauthorized;
    }
    if (statusCode == 404) return AppErrorKind.notFound;
    if (statusCode == 429) return AppErrorKind.rateLimited;
    if (statusCode >= 500) return AppErrorKind.serverError;
    return AppErrorKind.badRequest;
  }

  /// Short, human-facing copy. One place to localise later.
  String get userMessage => switch (kind) {
    AppErrorKind.offline => 'You appear to be offline. Check your connection.',
    AppErrorKind.timeout => 'The server did not answer in time. Try again.',
    AppErrorKind.unauthorized => 'Sign-in problem. Please log in again.',
    AppErrorKind.notFound => 'We could not find that content.',
    AppErrorKind.rateLimited => 'Too many requests. Give it a minute.',
    AppErrorKind.serverError => 'The service is having trouble right now.',
    AppErrorKind.parse => 'We received an unexpected response.',
    AppErrorKind.badRequest => 'That request was not valid.',
    AppErrorKind.unknown => 'Something went wrong. Try again.',
  };

  @override
  String toString() =>
      'AppError(${kind.name}): $message'
      '${cause == null ? '' : ' | cause: $cause'}';
}
