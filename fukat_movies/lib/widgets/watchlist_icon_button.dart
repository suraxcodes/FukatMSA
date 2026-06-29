import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/watchlist_service.dart';
import 'focusable_button.dart';

class WatchlistIconButton extends StatefulWidget {
  final String tmdbId;
  final String title;
  final String? posterPath;
  final bool isMovie;
  final bool isAnime;
  final bool showText;
  final String text;

  WatchlistIconButton({
    required this.tmdbId,
    required this.title,
    required this.posterPath,
    required this.isMovie,
    this.isAnime = false,
    this.showText = false,
    this.text = 'SAVE',
  });

  @override
  _WatchlistIconButtonState createState() => _WatchlistIconButtonState();
}

class _WatchlistIconButtonState extends State<WatchlistIconButton> {
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await WatchlistService.isSaved(widget.tmdbId);
    setState(() {
      _isSaved = saved;
    });
  }

  void _toggleWatchlist() async {
    await WatchlistService.toggleItem(
      widget.tmdbId,
      widget.title,
      widget.posterPath,
      widget.isMovie,
      isAnime: widget.isAnime,
    );
    // Refresh saved state after toggle
    final saved = await WatchlistService.isSaved(widget.tmdbId);
    setState(() {
      _isSaved = saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: WatchlistService.listenable,
      builder: (context, box, _) {
        // Update saved state based on box changes
        _isSaved = box.containsKey(widget.tmdbId);
        Widget iconWidget = Icon(
          _isSaved ? Icons.bookmark : Icons.bookmark_border,
          color: _isSaved ? Colors.redAccent : Colors.white,
        );

        if (widget.showText) {
          iconWidget = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              Text(
                _isSaved ? 'SAVED' : widget.text,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          );
        }

        return FocusableButton(
          onTap: _toggleWatchlist,
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
          child: iconWidget,
        );
      },
    );
  }
}
