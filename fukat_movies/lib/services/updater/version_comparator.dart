class VersionComparator {
  /// Compares two semver strings (e.g., '1.0.0' and '1.0.1').
  /// Returns true if [latestVersion] is strictly greater than [currentVersion].
  static bool isUpdateAvailable(String currentVersion, String latestVersion) {
    try {
      final currentParts = currentVersion.split('+').first.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = latestVersion.split('+').first.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final curr = i < currentParts.length ? currentParts[i] : 0;
        final latest = i < latestParts.length ? latestParts[i] : 0;
        if (latest > curr) return true;
        if (latest < curr) return false;
      }
      return false;
    } catch (e) {
      print("Error comparing versions: $e");
      return false;
    }
  }
}
