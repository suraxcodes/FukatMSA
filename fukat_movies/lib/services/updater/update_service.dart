import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fukat_MSA/services/updater/github_release_api.dart';
import 'package:fukat_MSA/services/updater/version_comparator.dart';
import 'package:fukat_MSA/ui/updater/update_dialog.dart';

class UpdateService {
  static bool _hasCheckedThisSession = false;

  /// Checks for an update and displays the UpdateDialog if one is available.
  /// This should be called once when the main Home screen mounts.
  static Future<void> checkForUpdates(BuildContext context) async {
    print("UpdateService: Checking for updates...");
    if (_hasCheckedThisSession) {
      print("UpdateService: Already checked this session. Skipping.");
      return;
    }
    _hasCheckedThisSession = true;

    try {
      // 1. Get current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      print("UpdateService: Current installed version is \$currentVersion");

      // 2. Get latest from GitHub
      final releaseData = await GitHubReleaseApi.getLatestRelease();
      if (releaseData == null) {
        print("UpdateService: Failed to fetch from GitHub or no APK found.");
        return; // API failed or no APK found
      }

      final latestVersion = releaseData['version'] as String;
      final releaseNotes = releaseData['notes'] as String;
      final downloadUrl = releaseData['downloadUrl'] as String;
      print("UpdateService: Latest GitHub version is \$latestVersion");
      print("UpdateService: Download URL is \$downloadUrl");

      // 3. Compare versions
      final isUpdateAvailable = VersionComparator.isUpdateAvailable(currentVersion, latestVersion);

      if (isUpdateAvailable) {
        // Ensure storage permission is requested (required on some older Androids for downloading)
        if (await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
        
        // Ensure install packages permission is requested
        if (await Permission.requestInstallPackages.isDenied) {
          await Permission.requestInstallPackages.request();
        }

        if (context.mounted) {
          showGeneralDialog(
            context: context,
            barrierDismissible: false,
            pageBuilder: (context, animation, secondaryAnimation) {
              return UpdateDialog(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                releaseNotes: releaseNotes,
                downloadUrl: downloadUrl,
              );
            },
          );
        }
      }
    } catch (e) {
      print("UpdateService error: $e");
    }
  }
}
