# FukatMovies - Provider First Development Update

## Priority Shift: Provider Stability Before UI

Before building the full UI, animations, layouts, banners, or platform-specific designs, the first focus of the project will be validating the entire streaming pipeline.

The app must first prove that it can:

* Successfully fetch Movies, Series, and Anime metadata.
* Successfully resolve streaming links from providers.
* Successfully stream videos without crashes.
* Handle provider failures and fallback correctly.
* Switch between providers automatically.
* Support different content types consistently.
* Confirm subtitles, quality selection, and episode fetching work properly.

The UI should only be built after the provider system is stable. Otherwise, there is no point building a polished frontend on top of broken or unreliable streaming sources.

---

## Updated Development Roadmap

### Phase 1: Provider & Streaming Validation (Highest Priority)

The first development phase is focused entirely on testing providers and streaming reliability.

### Goals

* Verify Movie fetching works.
* Verify Series fetching works.
* Verify Anime fetching works.
* Verify episode scraping works.
* Verify stream extraction works.
* Verify playback works using `media_kit`.
* Test multiple providers simultaneously.
* Build fallback logic between providers.
* Test buffering behavior.
* Test quality switching.
* Test subtitle loading.
* Confirm streams work across Mobile, TV, and Desktop.

### Initial Development Flow

1. Fetch content from TMDB/AniList.
2. Resolve provider sources.
3. Extract playable `.m3u8` or `.mp4` links.
4. Test playback directly in a minimal test player.
5. Stress test provider failures.
6. Add caching and fallback handling.
7. Only after stable streaming, begin UI development.

---

## UI Development Comes Later

The final Netflix-style UI, Hero banners, animations, category rows, and advanced layouts will be developed only after:

* Providers are stable.
* Streaming works reliably.
* Episode switching works.
* Auto fallback works.
* Buffering mitigation works.
* Playback works consistently.

This prevents wasting time building a large UI system before confirming the core streaming engine actually functions properly.

---

## Updated Core Philosophy

### New Primary Rule

> A streaming app is useless if providers fail. The backend logic and stream reliability matter more than UI during early development.

The app should first behave like a stable streaming engine. The polished Netflix-level experience comes after the foundation is proven reliable.
