import 'package:apk_sideload/install_apk.dart';

class InstallerService {
  /// Launches the Android Package Installer for the given [filePath].
  static Future<bool> installApk(String filePath) async {
    try {
      await InstallApk().installApk(filePath);
      return true;
    } catch (e) {
      print("InstallerService error: $e");
      return false;
    }
  }
}
