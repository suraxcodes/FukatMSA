import '../screens/player_screen.dart';

/// Simple controller that forwards episode and audio change events to the
/// PlayerScreenState instance. It does not expose streams – the state is
/// updated via direct callbacks, matching the user's request for simple
/// state‑callback handling.
class EpisodeController {
  final PlayerScreenState _state;

  EpisodeController(this._state);

  void onEpisodeSelected(String season, String episode) {
    _state.onEpisodeSelected(season, episode);
  }

  void onAudioChanged(bool isDub) {
    _state.onAudioChanged(isDub);
  }
}
