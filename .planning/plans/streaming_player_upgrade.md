# Streaming Player Upgrade Plan

This implementation plan details the architectural and UI changes necessary to upgrade the video player in `fukat_movies` to support advanced streaming capabilities like auto-failover, adaptive quality, track selection, and robust provider queueing.

## Proposed Changes

### 1. Provider Queue & Server Dropdown

Current architecture already searches in batches of 3, stores successful providers in `_extractedProviderData`, and auto-plays the first successful one.

#### [MODIFY] `lib/screens/player_screen.dart`
- **Server Dropdown Filter**: Update `_buildServerSelector()` to iterate **only over `_successfulProviders`** instead of all `providers`. Failed or pending providers will be naturally hidden from the user.
- **Server Switching Without Re-fetch**: When a user selects a server from the dropdown, we will instantly call `_playFromProvider` using the cached data in `_extractedProviderData` instead of initiating a new network extraction.

### 2. Audio-Only Stream Detection & Auto Failover

#### [MODIFY] `lib/screens/player_screen.dart`
- **Health Check Timer**: Introduce a periodic check (every 2-3 seconds) once playback begins.
- **Detection Logic**: If `player.state.playing` is true and `player.state.position` is advancing, but `player.state.width == 0` or `player.state.height == 0` for over 10-15 seconds, we flag the stream as Audio-Only.
- **Auto Failover**: On Audio-Only detection, or if `player.stream.error` fires:
  1. Save `player.state.position`.
  2. Find the next available index in `_successfulProviders`.
  3. Call `_playFromProvider` with the next index.
  4. Automatically seek to the saved position.

### 3. Audio & Subtitle Track Selectors

#### [MODIFY] `lib/screens/player_screen.dart`
- **Track Metadata**: `media_kit` automatically parses embedded HLS/DASH tracks. We will read `player.state.tracks.audio` and `player.state.tracks.subtitle`.
- **UI Buttons**: Add an Audio icon and a Subtitle (CC) icon next to the Server Dropdown.
- **Selection Menus**: 
  - Tapping Audio opens a bottom sheet listing all `AudioTrack` objects with their language codes.
  - Tapping Subtitles opens a bottom sheet listing all `SubtitleTrack` objects, plus an "Off" option.

### 4. Video Quality Selector & Auto Mode

#### [MODIFY] `lib/screens/player_screen.dart`
- **Quality Options**: When an extractor returns a master `.m3u8` playlist, `media_kit` automatically adapts quality (Auto Mode).
- **Manual Quality Override**: If the provider explicitly returns multiple distinct `.mp4` URLs or specific `.m3u8` resolutions in `playbackData['streams']`, we will parse them into a Video Quality menu.
- **Quality UI**: Add a Settings/Gear icon to switch between "Auto" and specific resolutions (1080p, 720p, etc.).
- **State Preservation**: When switching quality, we save the timestamp, reload the new URL, and seek back to the exact same spot seamlessly.
