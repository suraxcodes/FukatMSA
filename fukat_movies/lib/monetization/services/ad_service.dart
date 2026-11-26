import 'package:flutter/material.dart';

abstract class AdService {
  Future<void> showInterstitialAd(BuildContext context);
}

class MockAdService implements AdService {
  // Master toggle to turn mock ads ON or OFF during development
  // make it true when you need to add ads 
  static bool enableMockAds = false;

  @override
  Future<void> showInterstitialAd(BuildContext context) async {
    if (!enableMockAds) return;

    // Show a mock full-screen ad
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black87,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.ad_units, size: 64, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Mock Interstitial Ad',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Loading your video in 3 seconds...',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(color: Colors.redAccent),
              ],
            ),
          ),
        );
      },
    );

    // Wait 3 seconds
    await Future.delayed(const Duration(seconds: 3));

    // Close the ad dialog if it is still mounted
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
