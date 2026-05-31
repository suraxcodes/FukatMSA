import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A sheet that allows the user to pick a season and episode for a series.
///
/// The UI presents a banner image of the series with a centered play button.
/// Below the banner, dropdown selectors let the user choose a season and an
/// episode. When the "Play" button is pressed, the selected values are passed
/// to the provided [onPlayPressed] callback.
class EpisodePickerSheet extends StatefulWidget {
  final String currentSeason;
  final String currentEpisode;
  final String bannerUrl; // URL of the series banner image.
  final Function(String season, String episode) onPlayPressed;

  const EpisodePickerSheet({
    Key? key,
    required this.currentSeason,
    required this.currentEpisode,
    required this.bannerUrl,
    required this.onPlayPressed,
  }) : super(key: key);

  @override
  State<EpisodePickerSheet> createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<EpisodePickerSheet> {
  late String _selectedSeason;
  late String _selectedEpisode;

  // Dummy data – replace with real data from TMDB or your service.
  final List<String> _seasons = List.generate(5, (i) => '${i + 1}');
  final Map<String, List<String>> _episodesPerSeason = {
    for (var i = 1; i <= 5; i++) '$i': List.generate(10, (j) => '${j + 1}'),
  };

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
    _selectedEpisode = widget.currentEpisode;
  }

  List<String> get _currentEpisodes =>
      _episodesPerSeason[_selectedSeason] ?? ['1'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bannerHeight = MediaQuery.of(context).size.height * 0.3;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner with overlay play button
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: widget.bannerUrl,
                    height: bannerHeight,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => Container(
                      height: bannerHeight,
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (ctx, url, error) => Container(
                      height: bannerHeight,
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                      child: const Center(child: Icon(Icons.broken_image, size: 48)),
                    ),
                  ),
                ),
                // Play button overlay
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: _onPlay,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black45,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const Icon(Icons.play_arrow, size: 48, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Season selector
            _buildDropdown(
              label: 'Season',
              value: _selectedSeason,
              items: _seasons,
              onChanged: (val) {
                if (val != null && val != _selectedSeason) {
                  setState(() {
                    _selectedSeason = val;
                    // Reset episode to first of new season
                    _selectedEpisode = _episodesPerSeason[val]!.first;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            // Episode selector
            _buildDropdown(
              label: 'Episode',
              value: _selectedEpisode,
              items: _currentEpisodes,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedEpisode = val);
                }
              },
            ),
            const SizedBox(height: 24),
            // Play button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: const Text('Play', style: TextStyle(fontSize: 16, color: Colors.white)),
              onPressed: _onPlay,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.grey[900],
          iconEnabledColor: Colors.white70,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white))) )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _onPlay() {
    widget.onPlayPressed(_selectedSeason, _selectedEpisode);
    Navigator.of(context).pop();
  }
}
