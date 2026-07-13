import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ApkDownloader {
  /// Downloads an APK from the provided [url] to the device's temporary directory.
  /// Calls [onProgress] with the current bytes and total bytes downloaded.
  /// Returns the local path to the downloaded APK, or null if failed.
  static Future<String?> downloadApk(String url, Function(int, int) onProgress, {CancelToken? cancelToken}) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/update.apk';
      final file = File(filePath);

      // Clean up any old update files
      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      return filePath;
    } catch (e) {
      print("ApkDownloader error: $e");
      return null;
    }
  }
}
