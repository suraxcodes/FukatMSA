import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/tmdb_service.dart';
import 'package:flutter/gestures.dart';

/// Side panel (or bottom panel on mobile) UI for selecting season & episode.
/// It receives the list of seasons and episodes per season generated from TMDB.
class EpisodeSidePanel extends StatefulWidget {
  final String tmdbId;
  final String currentSeason;
  final String currentEpisode;
  final void Function(String season, String episode) onEpisodeSelected;
  final List<String> seasons;
  final bool isDub;
  final bool hasDub;
  final ValueChanged<bool> onAudioChanged;
  final Set<String> watchedEpisodes;
  final Map<String, int> seasonEpisodeCounts;

  const EpisodeSidePanel({
    Key? key,
    required this.tmdbId,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
    required this.seasons,
    this.isDub = false,
    this.hasDub = false,
    required this.onAudioChanged,
    required this.watchedEpisodes,
    this.seasonEpisodeCounts = const {},
  }) : super(key: key);

  @override
  State<EpisodeSidePanel> createState() => _EpisodeSidePanelState();
}

class _EpisodeSidePanelState extends State<EpisodeSidePanel> {
  late String _selectedSeason;
  List<String> _currentEpisodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
    _loadEpisodesForActiveSeason(_selectedSeason);
  }

  Future<void> _loadEpisodesForActiveSeason(String seasonNumber) async {
    setState(() => _isLoading = true);
    
    // Fetch ONLY the active season directly from the server
    final episodes = await TmdbService.getSeasonEpisodes(
      int.parse(widget.tmdbId), 
      int.parse(seasonNumber)
    );
    
    if (mounted) {
      setState(() {
        _currentEpisodes = episodes.map((e) => e['episode_number'].toString()).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414), // Dark background
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: "Episodes" and "X seasons" badge
          Row(
            children: [
              const Icon(Icons.format_list_numbered, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Episodes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${widget.seasons.length} seasons',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Seasons Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'SEASONS',
                style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.seasons.map((season) {
                      final isSelected = season == _selectedSeason;
                      int watchedCount = widget.watchedEpisodes.where((e) => e.startsWith("${season}_")).length;
                      int totalCount = widget.seasonEpisodeCounts[season] ?? 0;
                      bool isSeasonWatched = totalCount > 0 && watchedCount >= totalCount;
                      print("Season: $season, Watched: $watchedCount, Total: $totalCount, IsWatched: $isSeasonWatched");
                      
                      final BoxDecoration defaultDec = BoxDecoration(
                        color: isSelected ? const Color(0xFF8A2BE2) : (isSeasonWatched ? const Color(0xFF111111) : const Color(0xFF222222)),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isSelected ? [
                          BoxShadow(color: const Color(0xFF8A2BE2).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                        ] : null,
                      );
                      
                      final BoxDecoration focusedDec = defaultDec.copyWith(
                        border: Border.all(color: Colors.white, width: 2),
                      );

                      return _FocusableButton(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        defaultDecoration: defaultDec,
                        focusedDecoration: focusedDec,
                        onTap: () {
                          if (!isSelected) {
                            setState(() => _selectedSeason = season);
                            _loadEpisodesForActiveSeason(season);
                          }
                        },
                        child: Text(
                          'S$season',
                          style: TextStyle(
                            color: isSelected ? Colors.white : (isSeasonWatched ? Colors.white24 : Colors.white),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Episode Title / Indicator
          Text(
            'Season $_selectedSeason · Episode ${widget.currentEpisode}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Episodes Row
          _isLoading 
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF8A2BE2))),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _currentEpisodes.map((ep) {
                    final isPlaying = (ep == widget.currentEpisode && _selectedSeason == widget.currentSeason);
                    final isWatched = widget.watchedEpisodes.contains("${_selectedSeason}_$ep");
                    
                    final BoxDecoration defaultDec = BoxDecoration(
                      color: isPlaying ? Colors.cyan : (isWatched ? const Color(0xFF111111) : const Color(0xFF222222)),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isPlaying ? [
                          BoxShadow(color: Colors.cyan.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                        ] : null,
                    );
                    
                    final BoxDecoration focusedDec = defaultDec.copyWith(
                      border: Border.all(color: Colors.white, width: 2),
                    );

                    return _FocusableButton(
                      margin: const EdgeInsets.only(right: 12),
                      defaultDecoration: defaultDec,
                      focusedDecoration: focusedDec,
                      onTap: () => widget.onEpisodeSelected(_selectedSeason, ep),
                      child: Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        child: Text(
                          ep,
                          style: TextStyle(
                            color: isPlaying ? Colors.black : (isWatched ? Colors.white24 : Colors.white),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          const SizedBox(height: 16),
          // Legend (Aesthetic placeholder to match design)
          Row(
            children: [
              _buildLegendDot(Colors.cyan, 'Now playing'),
              const SizedBox(width: 16),
              _buildLegendIcon(Icons.check, Colors.greenAccent, 'Available'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.greenAccent, 'New'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildLegendIcon(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}

class _FocusableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BoxDecoration defaultDecoration;
  final BoxDecoration focusedDecoration;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const _FocusableButton({
    Key? key,
    required this.child,
    required this.onTap,
    required this.defaultDecoration,
    required this.focusedDecoration,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
  }) : super(key: key);

  @override
  State<_FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<_FocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: Container(
            padding: widget.padding,
            decoration: _isFocused ? widget.focusedDecoration : widget.defaultDecoration,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

