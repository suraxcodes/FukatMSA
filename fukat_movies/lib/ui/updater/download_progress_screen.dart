import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fukat_MSA/services/updater/apk_downloader.dart';
import 'package:fukat_MSA/services/updater/installer_service.dart';

class DownloadProgressScreen extends StatefulWidget {
  final String downloadUrl;
  final String version;

  const DownloadProgressScreen({
    Key? key,
    required this.downloadUrl,
    required this.version,
  }) : super(key: key);

  @override
  State<DownloadProgressScreen> createState() => _DownloadProgressScreenState();
}

class _DownloadProgressScreenState extends State<DownloadProgressScreen> {
  double _progress = 0.0;
  String _downloaded = "0 MB";
  String _total = "0 MB";
  bool _isError = false;
  bool _isInstalling = false;
  bool _isCancelled = false;
  
  CancelToken? _cancelToken;
  
  final FocusNode _retryFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _retryFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _startDownload() async {
    _cancelToken = CancelToken();
    setState(() {
      _isError = false;
      _isCancelled = false;
      _progress = 0.0;
    });

    final path = await ApkDownloader.downloadApk(
      widget.downloadUrl,
      (received, total) {
        if (total != -1) {
          setState(() {
            _progress = received / total;
            _downloaded = (received / 1024 / 1024).toStringAsFixed(1) + " MB";
            _total = (total / 1024 / 1024).toStringAsFixed(1) + " MB";
          });
        }
      },
      cancelToken: _cancelToken,
    );

    if (_cancelToken?.isCancelled == true || _isCancelled) {
      // User cancelled
      return;
    }

    if (path == null) {
      setState(() {
        _isError = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _retryFocusNode.requestFocus();
      });
    } else {
      setState(() {
        _isInstalling = true;
      });
      final success = await InstallerService.installApk(path);
      if (!success) {
        setState(() {
          _isError = true;
          _isInstalling = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _retryFocusNode.requestFocus();
        });
      } else {
        // Installation launched successfully
        Navigator.of(context).pop();
      }
    }
  }

  void _cancelDownload() {
    setState(() {
      _isCancelled = true;
    });
    _cancelToken?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isInstalling 
                    ? "Launching Installer..." 
                    : _isError 
                        ? "Download Failed" 
                        : "Downloading Update...",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              if (!_isError && !_isInstalling) ...[
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 12,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${(_progress * 100).toInt()}%",
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    Text(
                      "$_downloaded / $_total",
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  focusNode: _cancelFocusNode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ).copyWith(
                    backgroundColor: MaterialStateProperty.resolveWith((states) {
                      return states.contains(MaterialState.focused) ? Colors.white24 : Colors.transparent;
                    }),
                  ),
                  onPressed: _cancelDownload,
                  child: const Text("Cancel"),
                ),
              ],
              if (_isInstalling) ...[
                const CircularProgressIndicator(color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  "Please follow the system prompts to install the update.",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_isError) ...[
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                const Text(
                  "There was a network error or the installation was cancelled.",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      focusNode: _cancelFocusNode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ).copyWith(
                        backgroundColor: MaterialStateProperty.resolveWith((states) {
                          return states.contains(MaterialState.focused) ? Colors.white24 : Colors.transparent;
                        }),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      focusNode: _retryFocusNode,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ).copyWith(
                        backgroundColor: MaterialStateProperty.resolveWith((states) {
                          return states.contains(MaterialState.focused) ? Colors.blue : Colors.blueAccent.withOpacity(0.8);
                        }),
                      ),
                      onPressed: _startDownload,
                      child: const Text("Retry"),
                    ),
                  ],
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}
