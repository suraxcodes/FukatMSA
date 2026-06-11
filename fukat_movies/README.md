# FukatMovies (FukatMSA)

A comprehensive movie and media streaming application built with Flutter. This project leverages a variety of modern frameworks, libraries, and best practices to deliver a seamless, high-performance streaming experience across platforms.

## Technology Stack & Frameworks

### Core Framework
* **[Flutter](https://flutter.dev/)**
  * **Why:** Flutter is used as the foundational UI framework to enable true cross-platform development from a single Dart codebase. It provides native-like performance and allows for highly customized, beautiful user interfaces optimized for media consumption.

### Media & Video Playback
* **[media_kit](https://pub.dev/packages/media_kit) & [media_kit_video](https://pub.dev/packages/media_kit_video)**
  * **Why:** A robust, high-performance video player based on `mpv`. Standard Flutter video players often struggle with complex codecs, HLS streaming, or advanced subtitle rendering. `media_kit` provides native hardware acceleration, widespread format support, and deep customization, making it the perfect engine for a robust movie streaming app.

### Networking & Web Integration
* **[http](https://pub.dev/packages/http)**
  * **Why:** For making standard REST API calls to backend services, media providers, and metadata databases (like TMDB/IMDB). It is lightweight and easy to use for fetching JSON data.
* **[flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview)**
  * **Why:** Sometimes, streaming links are protected by captchas or are deeply embedded in third-party web players. This package allows the app to load complex web pages invisibly or visibly to extract streaming URLs, bypass web-level protections, or display external media players directly in the app.

### Data Persistence & Caching
* **[Hive](https://pub.dev/packages/hive) & [hive_flutter](https://pub.dev/packages/hive_flutter)**
  * **Why:** A blazing-fast, lightweight NoSQL database used for local storage. In a media app, Hive is ideal for caching user data like "Watch History," "Favorites," and "Watchlist" locally so the app remains responsive and usable even with poor network connections.
* **[cached_network_image](https://pub.dev/packages/cached_network_image)**
  * **Why:** A movie app relies heavily on high-quality visual assets (posters, banners, thumbnails). This library automatically handles downloading and caching images locally, significantly reducing bandwidth usage and loading times for end users on subsequent app opens.
* **[shared_preferences](https://pub.dev/packages/shared_preferences)**
  * **Why:** Used for storing simple user preferences (e.g., dark/light mode, default subtitle language, video quality settings) in a key-value format.

### Backend & Authentication
* **[supabase_flutter](https://pub.dev/packages/supabase_flutter)**
  * **Why:** Supabase acts as the primary backend-as-a-service (BaaS). It provides scalable PostgreSQL database hosting, real-time subscriptions, and authentication (login/signup). It is an open-source alternative to Firebase and handles cross-device syncing of watchlists and user accounts.

### Utility & Configuration
* **[flutter_dotenv](https://pub.dev/packages/flutter_dotenv)**
  * **Why:** Security best practices. It allows the app to load environment variables from a `.env` file. This ensures that sensitive API keys, Supabase credentials, and backend URLs are not hardcoded into the source code.
* **[connectivity_plus](https://pub.dev/packages/connectivity_plus)**
  * **Why:** Crucial for a streaming app to monitor the user's internet connection. It allows the app to intelligently pause downloads, warn users when they switch from Wi-Fi to Cellular data, or show an "offline" UI when the internet drops.
* **[mobile_scanner](https://pub.dev/packages/mobile_scanner)**
  * **Why:** Enables QR code and barcode scanning capabilities. In this app, it is used in the Settings screen to allow users to quickly scan a QR code to enter a "Custom Repository URL" instead of typing long web addresses manually.
* **[fluttertoast](https://pub.dev/packages/fluttertoast)**
  * **Why:** For displaying quick, non-intrusive feedback to the user (e.g., "Added to Watchlist", "Link copied", or error states) without interrupting the viewing experience.

## Getting Started

### Prerequisites
1. Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed (Version 3.11.1 or higher).
2. Ensure you have the necessary `.env` files and configuration defined in the `assets/` directory.

### Installation
1. Clone the repository.
2. Run `flutter pub get` to install all dependencies.
3. Run `flutter run` to build and launch the application on your connected device or emulator.
