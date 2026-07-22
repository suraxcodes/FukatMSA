# Project Change Log

---

## Date
2026-07-13 21:03

## Task
Add Anime Scraper

## Reason
Enable anime streaming in the app.

## what problem/error we fixed
Added new functionality to scrape anime using Hianime.

## Files Changed
- fukat-scraper-api/animescraper/animeHandler.js
- fukat-scraper-api/server.js
- fukat-scraper-api/package.json (updated @consumet/extensions)

## Main Changes
- Created `animescraper/animeHandler.js` with logic for Hianime scraper.
- Updated `server.js` to route `type='anime'` requests to the new handler.
- Updated `@consumet/extensions` to the latest version to ensure anime scrapers work.
- New features: Anime searching and episode extraction.

## Technical Notes
- The anime scraping logic relies on `ANIME.Hianime` from `@consumet/extensions`. 
- Anime requests expect `type=anime` and a `title`.
- If a specific `episode` query parameter is not provided, it defaults to the first episode.

## Breaking Changes
None

## Status
Completed

---

## Date
2026-07-13 21:43

## Task
Create Client-Side Headless Dart Scraper

## Reason
Enable client-side scraping for anime directly on device.

## what problem/error we fixed
Node.js scrapers cannot run directly in a Flutter app, so we needed a Dart alternative that bypasses Cloudflare protections using WebViews.

## Files Changed
- lib/services/anime_scraper_service.dart

## Main Changes
- Created `anime_scraper_service.dart` featuring a `HeadlessInAppWebView`.
- Implemented logic to silently load anime pages in the background.
- Added JavaScript injection to extract `video` tags, `iframe` sources, or raw `.m3u8` links directly from the loaded DOM.

## Technical Notes
- Uses `flutter_inappwebview` package.
- It returns a Future containing the stream URL string, timing out after 15 seconds if nothing is found.
- The `HeadlessInAppWebView` avoids CORS/Cloudflare issues by simulating a real browser environment.

## Breaking Changes
None

## Status
Completed

---

---

## Date
2026-07-15 12:37

## Task
Remove Stremio Scraper

## Reason
Speeds up playback failover.

## what problem/error we fixed
Removed Stremio from remote_config to prevent wasting 3 seconds failing to fetch magnet links without Real-Debrid.

## Files Changed
- assets/remote_config.json

## Main Changes
- Removed Stremio Server from active_providers list.

## Technical Notes
Stremio addons return infoHashes/magnets instead of HTTP links unless a premium Debrid account is used. Skipping it speeds up WebView failover.

## Breaking Changes
None

## Status
Completed

---

---

## Date
2026-07-15 12:41

## Task
Invisible Webview Scraper Integration

## Reason
Bypass Cloudflare entirely on-device without a server.

## what problem/error we fixed
Pure Dart HTTP requests get blocked by Cloudflare (error 121 / 503). Added a Headless Webview engine to mimic a browser, execute JS, and extract the raw .m3u8 stream to play in the native video player.

## Files Changed
- lib/services/headless_extractor_service.dart
- lib/services/streaming_aggregator_service.dart
- lib/screens/player_screen.dart
- lib/player/playback_manager.dart
- assets/remote_config.json

## Main Changes
- Created HeadlessExtractorService using HeadlessInAppWebView.
- Intercepts onLoadResource to sniff for .m3u8 streams.
- Updated PlayerScreen to show 'Extracting Direct Stream...' while headless webview runs.
- Added Headless Anime Scraper to remote_config.

## Technical Notes
Headless Webviews are heavily resource-intensive. If they hang, there is a 15-second timeout before it fails over to the next provider.

## Breaking Changes
None

## Status
Completed

---

---

## Date
2025-07-15 12:00

## Task
Fix native extractor engine matching and id_type crash

## Reason
Anime scraper failed to stream due to engine rename mismatch.

## what problem/error we fixed
Fixed black screen and Null subtype crash caused by obsolete 'native_miruro' checks filtering out Anime providers and causing a crash on id_type parsing for fallback providers.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Replaced 'native_miruro' with 'native_extractor' in _isAnime and _activeProviders.
- Added fallback to provider['id_type'] in _buildPlaybackUrl to prevent null exception.

## Technical Notes
The Player UI state relies heavily on currentEngine. Any mismatch filters out providers and crashes the _isMappingEpisode UI state, leaving the player with a blank screen.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 09:40

## Task
Add autofocus to play button

## Reason
Enable starting playback with TV remote and keyboard.

## what problem/error we fixed
Users could not start playback using D-pad/Arrow keys because the initial Play button InkWell did not request focus.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Added autofocus: true to the play button InkWell in _buildVideoPlayerArea.

## Technical Notes
This ensures Flutter's focus engine lands on the play button when the player screen opens.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 09:43

## Task
Auto-start playback on player screen

## Reason
Bypass initial play button to instantly start stream.

## what problem/error we fixed
Users had to manually click play after opening the player screen, which was inconvenient for TV remote users.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Changed default value of _isPlaying from false to true.

## Technical Notes
This skips the play button overlay and triggers the stream extraction/playback initialization immediately on screen load.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 09:55

## Task
Fix TV remote play/pause focus loss

## Reason
Remote arrow keys threw focus out of video player.

## what problem/error we fixed
Users could not play/pause or navigate after pressing arrow keys because the custom Focus node aggressively intercepted them and pushed focus outside the player, leaving the player permanently unfocused and unresponsive to Enter/Select.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Removed manual interception of LogicalKeyboardKey.arrowLeft/Right/Up/Down from the Video widget's Focus node wrapper.

## Technical Notes
Native media_kit_video already handles DPAD navigation correctly. Stripping the aggressive forced focusInDirection traversal fixes remote control behavior for TV apps.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 10:00

## Task
Remove custom Focus wrapper to fix remote control Enter/Select hijacking

## Reason
Custom Focus node was intercepting Enter keys and breaking button interactions.

## what problem/error we fixed
Users could not use the remote 'OK/Enter' button to click UI elements like Settings or the native Play/Pause button because the parent Focus wrapper intercepted all Enter/Select keys and swallowed them, overriding Flutter's native focus traversal.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Completely removed the Focus wrapper wrapping the Video widget in _buildVideoPlayerArea.

## Technical Notes
Native media_kit_video and Flutter focus tree now handles all DPAD arrow keys and Enter keys natively, allowing users to actually 'click' the buttons on the screen with their remotes.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 10:04

## Task
Disable media_kit_video default shortcuts

## Reason
media_kit_video was stealing arrow keys to seek the video, breaking D-pad navigation.

## what problem/error we fixed
Users could not move between the on-screen buttons (Settings, Play, Subtitles) because the arrow keys were forcefully mapped to SeekForward/Backward by the video player engine. Disabled these native shortcuts to restore standard Flutter focus traversal.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Added keyboardShortcuts: {} to MaterialVideoControlsThemeData to disable all default media_kit shortcuts.

## Technical Notes
This fully restores standard Android TV / D-pad focus traversal between all MaterialVideoControls UI elements.

## Breaking Changes
None

## Status
Completed

---

## Date
2025-07-17 10:05

## Task
Fix compilation error with keyboardShortcuts

## Reason
media_kit_video version 2.0.1 does not support keyboardShortcuts.

## Files Changed
- lib/screens/player_screen.dart

## Main Changes
- Removed invalid parameter.

## Status
Completed
