import 'package:flutter/material.dart';
import '../services/manga_watchlist_service.dart';

class MangaWatchlistIconButton extends StatefulWidget {
  final Map<String, dynamic> manga;

  const MangaWatchlistIconButton({
    Key? key,
    required this.manga,
  }) : super(key: key);

  @override
  _MangaWatchlistIconButtonState createState() => _MangaWatchlistIconButtonState();
}

class _MangaWatchlistIconButtonState extends State<MangaWatchlistIconButton> {
  bool isSaved = false;

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
  }

  Future<void> _checkSavedStatus() async {
    final saved = await MangaWatchlistService.isSaved(widget.manga['id'].toString());
    if (mounted) {
      setState(() {
        isSaved = saved;
      });
    }
  }

  Future<void> _toggleSaved() async {
    await MangaWatchlistService.toggleManga(widget.manga);
    _checkSavedStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSaved ? "Removed from Watchlist" : "Added to Watchlist",
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isSaved ? Icons.bookmark : Icons.bookmark_border,
        color: isSaved ? Colors.redAccent : Colors.white,
      ),
      onPressed: _toggleSaved,
    );
  }
}
