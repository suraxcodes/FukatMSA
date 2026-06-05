import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import 'player_screen.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/services/ad_service.dart';

class SeriesDetailScreen extends StatefulWidget {
  final String tmdbId;
  final String title;
  const SeriesDetailScreen({required this.tmdbId, required this.title, Key? key}) : super(key: key);

  @override
  _SeriesDetailScreenState createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  Map<String, dynamic>? _details;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final data = await TmdbService.getSeriesDetails(int.parse(widget.tmdbId));
    setState(() {
      _details = data;
      _loading = false;
    });
  }

  void _openSeason(int seasonNumber) async {
    final episodes = await TmdbService.getSeasonEpisodes(int.parse(widget.tmdbId), seasonNumber);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      builder: (_) => _EpisodeSheet(
        seasonNumber: seasonNumber,
        episodes: episodes,
        seriesTitle: widget.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF141414),
        appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black),
        body: const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }
    final seasons = _details!['seasons'] as List;
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView.builder(
        itemCount: seasons.length,
        itemBuilder: (_, i) {
          final season = seasons[i];
          final name = season['name'];
          final number = season['season_number'];
          final poster = season['poster_path'];
          return ListTile(
            leading: poster != null
                ? Image.network('https://image.tmdb.org/t/p/w200$poster', width: 50, fit: BoxFit.cover)
                : const Icon(Icons.tv, color: Colors.white70),
            title: Text(name, style: const TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () => _openSeason(number),
          );
        },
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  final int seasonNumber;
  final List<dynamic> episodes;
  final String seriesTitle;
  const _EpisodeSheet({required this.seasonNumber, required this.episodes, required this.seriesTitle, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text('$seriesTitle – Season $seasonNumber',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Colors.white30),
            Expanded(
              child: ListView.builder(
                itemCount: episodes.length,
                itemBuilder: (_, i) {
                  final ep = episodes[i];
                  final title = ep['name'];
                  final epNum = ep['episode_number'];
                  final overview = ep['overview'] ?? '';
                  return ListTile(
                    title: Text('Ep $epNum – $title', style: const TextStyle(color: Colors.white70)),
                    subtitle: Text(overview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38)),
                    onTap: () async {
                      Navigator.pop(context);
                      if (!SupabaseAuthService.isPremium) {
                        await MockAdService().showInterstitialAd(context);
                      }
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            tmdbId: '${seasonNumber}_$epNum',
                            isMovie: false,
                            title: '$title (S$seasonNumber·E$epNum)',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
