import 'package:flutter/material.dart';

/// Side panel (or bottom panel on mobile) UI for selecting season & episode.
/// It receives the list of seasons and episodes per season generated from TMDB.
class EpisodeSidePanel extends StatefulWidget {
  final String currentSeason;
  final String currentEpisode;
  final void Function(String season, String episode) onEpisodeSelected;
  final List<String> seasons;
  final Map<String, List<String>> episodesPerSeason;

  const EpisodeSidePanel({
    Key? key,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
    required this.seasons,
    required this.episodesPerSeason,
  }) : super(key: key);

  @override
  State<EpisodeSidePanel> createState() => _EpisodeSidePanelState();
}

class _EpisodeSidePanelState extends State<EpisodeSidePanel> {
  late String _selectedSeason;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
  }

  List<String> get _currentEpisodes =>
      widget.episodesPerSeason[_selectedSeason] ?? [];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A), // Dark background matching UI theme
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
                child: _buildDarkDropdown(
                  value: 'Sub & Dub',
                  items: const ['Sub & Dub', 'Sub', 'Dub'],
                  onChanged: (val) {},
                ),
              ),
              const SizedBox(width: 8),
              // Season selector (displayed as “Season X”)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.seasons.contains(_selectedSeason) ? _selectedSeason : (widget.seasons.isNotEmpty ? widget.seasons.first : null),
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A2A),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      items: widget.seasons
                          .map((e) => DropdownMenuItem(value: e, child: Text('Season $e')))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSeason = val;
                          });
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
          Expanded(
            child: GridView.builder(
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
                      color: isPlaying ? const Color(0xFF8A2BE2) : const Color(0xFF2A2A2A),
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
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          dropdownColor: const Color(0xFF2A2A2A),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
