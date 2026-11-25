/// Remembers which providers actually play, so the app gets faster and more
/// automatic the more you use it.
///
/// Signals recorded per provider:
///   * `played`     — playback started and survived the startup window
///   * `failed`     — probe rejected it, or the player errored quickly
///   * `stalled`    — opened but never produced frames
///   * `lastOk`     — when it last worked (recency beats a stale good streak)
///
/// Ranking is a Wilson-style smoothed success rate, so a provider that went
/// 1-for-1 does not outrank one that went 40-for-45, and a provider with no
/// history sits in the middle rather than at the bottom.
///
/// Stored in SharedPreferences (not Hive) because it is tiny key/value state
/// that must be readable during the very first resolve, before any box opens.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/log.dart';

class ProviderStats {
  int played;
  int failed;
  int stalled;
  DateTime? lastOk;

  ProviderStats({
    this.played = 0,
    this.failed = 0,
    this.stalled = 0,
    this.lastOk,
  });

  Map<String, dynamic> toJson() => {
    'p': played,
    'f': failed,
    's': stalled,
    'l': lastOk?.millisecondsSinceEpoch,
  };

  static ProviderStats fromJson(Map<String, dynamic> json) => ProviderStats(
    played: (json['p'] as num?)?.toInt() ?? 0,
    failed: (json['f'] as num?)?.toInt() ?? 0,
    stalled: (json['s'] as num?)?.toInt() ?? 0,
    lastOk: json['l'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['l'] as int)
        : null,
  );

  int get attempts => played + failed + stalled;

  /// Smoothing prior: assume 2 successes out of 4 before we know anything,
  /// so an unknown provider scores ~0.5 instead of 0 or 1.
  double get reliability {
    const priorWins = 2.0;
    const priorTrials = 4.0;
    final wins = played + priorWins;
    final trials = attempts + priorTrials;
    var score = wins / trials;

    // Recency: something that worked within 3 days gets a nudge, something
    // that has been failing for a week gets pushed down.
    final last = lastOk;
    if (last != null) {
      final age = DateTime.now().difference(last);
      if (age.inDays <= 3) {
        score += 0.05;
      } else if (age.inDays > 7) {
        score -= 0.10;
      }
    }
    return score.clamp(0.0, 1.0);
  }

  /// Milliseconds of ranking bonus handed to [StreamProber].
  double get latencyBonus => (reliability - 0.5) * 40;
}

class ProviderReputation {
  ProviderReputation._();

  static const String _tag = 'Reputation';
  static const String _key = 'provider_reputation_v1';

  static Map<String, ProviderStats> _stats = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _stats = {
            for (final entry in decoded.entries)
              entry.key.toString(): ProviderStats.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
          };
        }
      }
      _loaded = true;
      Log.i(_tag, 'loaded stats for ${_stats.length} provider(s)');
    } catch (e) {
      Log.w(_tag, 'could not load stats', e);
      _loaded = true;
    }
  }

  static ProviderStats statsFor(String providerName) =>
      _stats[providerName] ??= ProviderStats();

  /// provider name → latency bonus, for StreamProber.rank().
  static Map<String, double> get bonuses => {
    for (final entry in _stats.entries) entry.key: entry.value.latencyBonus,
  };

  /// Providers ordered best-first. Used to seed the resolve order so the most
  /// reliable server is tried first instead of whatever the JSON order is.
  static List<String> get rankedProviderNames {
    final names = _stats.keys.toList()
      ..sort(
        (a, b) => statsFor(b).reliability.compareTo(statsFor(a).reliability),
      );
    return names;
  }

  static Future<void> recordSuccess(String providerName) async {
    final stats = statsFor(providerName);
    stats.played += 1;
    stats.lastOk = DateTime.now();
    await _persist();
  }

  static Future<void> recordFailure(String providerName) async {
    statsFor(providerName).failed += 1;
    await _persist();
  }

  static Future<void> recordStall(String providerName) async {
    statsFor(providerName).stalled += 1;
    await _persist();
  }

  static Future<void> reset() async {
    _stats = {};
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({for (final e in _stats.entries) e.key: e.value.toJson()}),
      );
    } catch (e) {
      Log.w(_tag, 'could not persist stats', e);
    }
  }
}
