import 'package:flutter/material.dart';
import 'package:fukat_MSA/ui/updater/download_progress_screen.dart';

class UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateDialog({
    Key? key,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  }) : super(key: key);

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final FocusNode _installFocusNode = FocusNode();
  final FocusNode _laterFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus on the "Install Update" button specifically for Android TV D-Pad
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _installFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _installFocusNode.dispose();
    _laterFocusNode.dispose();
    super.dispose();
  }

  void _onInstallPressed() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DownloadProgressScreen(
          downloadUrl: widget.downloadUrl,
          version: widget.latestVersion,
        ),
      ),
    );
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Update Available",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "A new version of the application is available.",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              Text(
                "Version:\nCurrent: ${widget.currentVersion}\nLatest: ${widget.latestVersion}",
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              const Text(
                "Release Notes:",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 150,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.releaseNotes,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    focusNode: _laterFocusNode,
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
                    child: const Text("Later"),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    focusNode: _installFocusNode,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ).copyWith(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        return states.contains(MaterialState.focused) ? Colors.blue : Colors.blueAccent.withOpacity(0.8);
                      }),
                    ),
                    onPressed: _onInstallPressed,
                    child: const Text("Install Update"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
