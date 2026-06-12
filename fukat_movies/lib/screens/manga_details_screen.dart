import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../services/manga_service.dart';
import 'manga_reader_screen.dart';
import 'manga_webview_screen.dart';
import '../widgets/manga_watchlist_icon_button.dart';

class MangaDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> manga;

  const MangaDetailsScreen({Key? key, required this.manga}) : super(key: key);

  @override
  _MangaDetailsScreenState createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends State<MangaDetailsScreen> {
  bool _isLoading = true;
  String? _mangadexId;
  List<dynamic> _chapters = [];

  @override
  void initState() {
    super.initState();
    _fetchMangaDexData();
  }

  Future<void> _fetchMangaDexData() async {
    final title = widget.manga['title']['english'] ?? widget.manga['title']['romaji'];
    
    // 1. Find the MangaDex ID by title
    _mangadexId = await MangaService.getMangadexIdByTitle(title);
    
    if (_mangadexId != null) {
      // 2. Fetch Chapters
      final chapters = await MangaService.getMangaChapters(_mangadexId!);
      setState(() {
        _chapters = chapters;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.manga['title']['english'] ?? widget.manga['title']['romaji'];
    final coverImage = widget.manga['coverImage']['large'];
    final description = widget.manga['description'] ?? 'No description available.';

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          MangaWatchlistIconButton(manga: widget.manga),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coverImage != null)
              Center(
                child: Image.network(
                  coverImage,
                  headers: const {'User-Agent': 'Mozilla/5.0'},
                  height: Platform.isWindows ? 200 : 300,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                description.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''), // strip basic html tags
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Chapters (English)",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.public, color: Colors.blueAccent, size: 18),
                    label: const Text("Search Web", style: TextStyle(color: Colors.blueAccent)),
                    onPressed: () {
                      final searchQuery = Uri.encodeComponent("Read $title manga online english");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MangaWebviewScreen(
                            url: "https://www.google.com/search?q=$searchQuery",
                            title: "Web Search: $title",
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: Colors.redAccent),
              ))
            else if (_chapters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "No English chapters found on MangaDex.",
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      icon: const Icon(Icons.search, color: Colors.white),
                      label: const Text("Search for Chapters on Web", style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        final searchQuery = Uri.encodeComponent("Read $title manga online english");
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MangaWebviewScreen(
                              url: "https://www.google.com/search?q=$searchQuery",
                              title: "Web Search: $title",
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final chapterAttrs = chapter['attributes'];
                  final chapterTitle = chapterAttrs['title'] ?? '';
                  final chapterNum = chapterAttrs['chapter'] ?? '?';
                  final externalUrl = chapterAttrs['externalUrl'];
                  final isExternal = externalUrl != null;
                  
                  return ListTile(
                    title: Text(
                      'Chapter $chapterNum' + (chapterTitle.isNotEmpty ? ' - $chapterTitle' : ''),
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: Icon(
                      isExternal ? Icons.open_in_browser : Icons.menu_book, 
                      color: isExternal ? Colors.blueAccent : Colors.white54
                    ),
                    subtitle: isExternal 
                        ? const Text("Read on Official Site", style: TextStyle(color: Colors.blueAccent, fontSize: 12)) 
                        : null,
                    onTap: () async {
                      if (isExternal) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MangaWebviewScreen(
                              url: externalUrl,
                              title: '$title - Ch $chapterNum',
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MangaReaderScreen(
                              chapterId: chapter['id'],
                              chapterNum: chapterNum.toString(),
                              mangaTitle: title,
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
