import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';

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
      color: Colors.black, // Changed to solid black
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top controls row
          Row(
            children: [
              // Placeholder Sub & Dub dropdown
              Expanded(
                flex: 2,
                child: widget.hasDub ? _buildDarkDropdown(
                  value: widget.isDub ? 'Dub' : 'Sub',
                  items: const ['Sub', 'Dub'],
                  onChanged: (val) {
                    if (val == 'Dub' && !widget.isDub) {
                      widget.onAudioChanged(true);
                    } else if (val == 'Sub' && widget.isDub) {
                      widget.onAudioChanged(false);
                    }
                  },
                ) : Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 14, 13, 13), // Match user's black
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Sub', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              // Season selector (displayed as “Season X”)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 14, 13, 13), // Match user's black
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.seasons.contains(_selectedSeason) ? _selectedSeason : (widget.seasons.isNotEmpty ? widget.seasons.first : null),
                      isExpanded: true,
                      dropdownColor: const Color.fromARGB(255, 14, 13, 13), // Match user's black
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      items: widget.seasons
                          .map((e) => DropdownMenuItem(value: e, child: Text('Season $e')))
                          .toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedSeason) {
                          setState(() {
                            _selectedSeason = val;
                          });
                          _loadEpisodesForActiveSeason(val);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Episodes grid
          _isLoading 
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF8A2BE2))),
              )
            : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currentEpisodes.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 60,
              childAspectRatio: 1.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (ctx, idx) {
              final ep = _currentEpisodes[idx];
              final bool isPlaying = (ep == widget.currentEpisode && _selectedSeason == widget.currentSeason);
              return GestureDetector(
                onTap: () => widget.onEpisodeSelected(_selectedSeason, ep),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isPlaying ? const Color(0xFF8A2BE2) : const Color.fromARGB(255, 14, 13, 13), // Match user's black
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ep,
                    style: TextStyle(
                      color: isPlaying ? Colors.white : Colors.white70,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDarkDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 14, 13, 13), // Match user's black
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          dropdownColor: const Color.fromARGB(255, 14, 13, 13), // Match user's black
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
