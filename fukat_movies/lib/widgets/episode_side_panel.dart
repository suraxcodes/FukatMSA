import 'package:flutter/material.dart';

/// Side panel (or bottom panel on mobile) UI for selecting season & episode.
///
/// Features:
///  • Top row with "Sub & Dub" placeholder, Season selector, and a "Find num!" button.
///  • Grid of episodes for the selected season.
class EpisodeSidePanel extends StatefulWidget {
  final String currentSeason;
  final String currentEpisode;
  final void Function(String season, String episode) onEpisodeSelected;

  const EpisodeSidePanel({
    Key? key,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
  }) : super(key: key);

  @override
  State<EpisodeSidePanel> createState() => _EpisodeSidePanelState();
}

class _EpisodeSidePanelState extends State<EpisodeSidePanel> {
  late String _selectedSeason;
  
  // Dummy data – replace with real TMDB data later.
  final List<String> _seasons = List.generate(5, (i) => '${i + 1}');
  final Map<String, List<String>> _episodesPerSeason = {
    for (var i = 1; i <= 5; i++) '$i': List.generate(12, (j) => '${j + 1}'),
  };

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
  }

  List<String> get _currentEpisodes =>
      _episodesPerSeason[_selectedSeason] ?? ['1'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A), // Dark grey background matching the image
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top controls row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildDarkDropdown(
                  value: 'Sub & Dub',
                  items: ['Sub & Dub', 'Sub', 'Dub'],
                  onChanged: (val) {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildDarkDropdown(
                  value: _selectedSeason,
                  items: _seasons,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedSeason = val;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {},
                  child: const Text('Find num!', style: TextStyle(fontSize: 12)),
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
                // Check if this episode is currently playing
                final bool isPlaying = (ep == widget.currentEpisode && _selectedSeason == widget.currentSeason);
                return GestureDetector(
                  onTap: () {
                    widget.onEpisodeSelected(_selectedSeason, ep);
                  },
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
          value: items.contains(value) ? value : items.first,
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
