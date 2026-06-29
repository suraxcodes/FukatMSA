import 'package:flutter/material.dart';
import '../services/manga_watchlist_service.dart';
import 'focusable_button.dart';

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
    return FocusableButton(
      onTap: _toggleSaved,
      defaultDecoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87,
        border: Border.all(color: Colors.transparent, width: 2),
      ),
      focusedDecoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87,
        border: Border.all(color: Colors.redAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withOpacity(0.6),
            blurRadius: 8,
            spreadRadius: 2,
          )
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: Icon(
        isSaved ? Icons.bookmark : Icons.bookmark_border,
        color: isSaved ? Colors.redAccent : Colors.white,
      ),
    );
  }
}
