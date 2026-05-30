import 'package:flutter/material.dart';

class EpisodePickerSheet extends StatefulWidget {
  final String currentSeason;
  final String currentEpisode;
  final Function(String, String) onPlayPressed;

  EpisodePickerSheet({
    required this.currentSeason,
    required this.currentEpisode,
    required this.onPlayPressed,
  });

  @override
  _EpisodePickerSheetState createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<EpisodePickerSheet> {
  late TextEditingController _seasonController;
  late TextEditingController _episodeController;

  @override
  void initState() {
    super.initState();
    _seasonController = TextEditingController(text: widget.currentSeason);
    _episodeController = TextEditingController(text: widget.currentEpisode);
  }

  @override
  void dispose() {
    _seasonController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Episode',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _seasonController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Season',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _episodeController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Episode',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                widget.onPlayPressed(
                  _seasonController.text.trim(),
                  _episodeController.text.trim(),
                );
                Navigator.pop(context);
              },
              child: Text(
                'Play',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}
