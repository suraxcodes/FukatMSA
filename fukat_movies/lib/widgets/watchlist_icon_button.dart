import 'package:flutter/material.dart';
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
    _isSaved = WatchlistService.isSaved(widget.tmdbId);
  }

  void _toggleWatchlist() async {
    await WatchlistService.toggleItem(
      widget.tmdbId,
      widget.title,
      widget.posterPath,
      widget.isMovie,
    );
    setState(() {
      _isSaved = !_isSaved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: WatchlistService.listenable,
      builder: (context, box, _) {
        _isSaved = WatchlistService.isSaved(widget.tmdbId);
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
