import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/watchlist_service.dart';

class WatchlistIconButton extends StatefulWidget {
  final String tmdbId;
  final String title;
  final String? posterPath;
  final bool isMovie;

  WatchlistIconButton({
    required this.tmdbId,
    required this.title,
    required this.posterPath,
    required this.isMovie,
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
        return IconButton(
          icon: Icon(
            _isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: _isSaved ? Colors.redAccent : Colors.white,
          ),
          onPressed: _toggleWatchlist,
        );
      },
    );
  }
}
