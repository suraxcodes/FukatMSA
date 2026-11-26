/// Ad slot interface.
///
/// The Premium tier used to be the only gate on a mock interstitial, and that
/// gate was self-granted. Both are gone. What remains is a single seam so that
/// a real ad network can be dropped in later without touching screens:
///
///   * [NoAds] — the default. Does nothing, costs nothing, ships nothing.
///   * [DebugInterstitial] — a visible placeholder so you can see where an
///     interstitial would appear. Only active in debug builds.
///
/// Wire a real implementation (AdMob / Unity / AppLovin) by implementing
/// [AdService] and swapping the instance in [Ads.instance].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract class AdService {
  /// Called when the player is about to open. Must resolve quickly —
  /// anything over ~1s of added latency is worse than the ad revenue.
  Future<void> onPlayerOpening(BuildContext context);
}

/// Default: absolutely nothing.
class NoAds implements AdService {
  const NoAds();

  @override
  Future<void> onPlayerOpening(BuildContext context) async {}
}

/// Shows a dismissible placeholder panel in debug builds only.
class DebugInterstitial implements AdService {
  const DebugInterstitial();

  @override
  Future<void> onPlayerOpening(BuildContext context) async {
    if (!kDebugMode || !context.mounted) return;
    // Non-blocking: a dial-out notice in the corner, not a modal that holds
    // the user hostage. Real interstitials should be skippable too.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Ad slot (debug placeholder)'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }
}

class Ads {
  Ads._();

  /// Swap this for your network's implementation when you have one.
  static AdService instance = kDebugMode
      ? const DebugInterstitial()
      : const NoAds();

  /// Convenience so call sites read `await Ads.showOnPlayerOpen(context)`.
  static Future<void> showOnPlayerOpen(BuildContext context) =>
      instance.onPlayerOpening(context);
}
