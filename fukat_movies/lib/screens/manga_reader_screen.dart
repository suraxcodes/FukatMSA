import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;
import '../services/manga_service.dart';

class MangaReaderScreen extends StatefulWidget {
  final String chapterId;
  final String chapterNum;
  final String mangaTitle;

  const MangaReaderScreen({
    Key? key,
    required this.chapterId,
    required this.chapterNum,
    required this.mangaTitle,
  }) : super(key: key);

  @override
  _MangaReaderScreenState createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  bool _isLoading = true;
  List<String> _pageUrls = [];
  int _currentPageIndex = 0;
  bool _isFullscreen = false;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _fetchPages();
  }

  Future<void> _fetchPages() async {
    final urls = await MangaService.getChapterPages(widget.chapterId);
    setState(() {
      _pageUrls = urls;
      _isLoading = false;
    });
  }

  void _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(_isFullscreen);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        windowManager.setFullScreen(false);
      } else if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Immersive reading
      appBar: _isFullscreen ? null : AppBar(
        title: Text('${widget.mangaTitle} - Ch ${widget.chapterNum}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      extendBodyBehindAppBar: true, // allows full screen reading
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _pageUrls.isEmpty
              ? const Center(child: Text("Failed to load pages.", style: TextStyle(color: Colors.white)))
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _pageUrls.length,
                      scrollBehavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      onPageChanged: (index) {
                        setState(() {
                          _currentPageIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        return InteractiveViewer(
                          panEnabled: true,
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.network(
                              _pageUrls[index],
                              headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(color: Colors.white30),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white54, size: 50),
                            ),
                          ),
                        );
                      },
                    ),
                    // Page Indicator Overlay and Fullscreen exit
                    Positioned(
                      bottom: 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Page ${_currentPageIndex + 1} / ${_pageUrls.length}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_isFullscreen) ...[
                              const SizedBox(width: 10),
                              Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                                  onPressed: _toggleFullscreen,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
