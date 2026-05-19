# GlassTube

A native macOS YouTube client built with SwiftUI and Apple's Liquid Glass design language.

## Install

1. Download the latest `GlassTube-*.zip` from [Releases](../../releases/latest).
2. Unzip and drag `GlassTube.app` to `/Applications`.
3. **First launch:** right-click `GlassTube.app` → **Open** → **Open**. Releases are unsigned, so Gatekeeper warns once.

> **Requires macOS 26 (Tahoe) or later.** Sign-in and downloads are optional (see [OAuth Setup](#oauth-setup-required-for-sign-in) and the `yt-dlp` note under [Requirements](#requirements)).

## Features

- **Liquid Glass UI** — sidebar, simplified single-surface search bar, player controls, and buttons all use Apple's glass effects
- **Video Player** — custom AVKit player with auto-hiding controls, draggable progress bar, SponsorBlock timeline markers, safe SponsorBlock auto-skip, volume/speed/quality settings, keyboard shortcuts, double-click seek, adaptive format playback (1080p+), and native Picture-in-Picture support
- **System Integration** — MPNowPlayingInfoCenter (Control Center), F7/F8/F9 media key support, title/channel/artwork displayed system-wide
- **Watch Page** — channel info, subscribe, like/dislike (with Return YouTube Dislike counts), share, download, comments (including in-app comment posting when signed in), DeArrow title replacement, SponsorBlock segment badges, and Innertube-powered suggested videos sidebar
- **In-App Watch Tabs** — opening any video creates a new watch tab in-app, with a browse tab and closable video tabs
- **Home Feed** — auth-aware YouTube data loading with adaptive video grid and channel avatars; resilient discovery fallback keeps Home populated when Innertube browse responses are sparse or invalid
- **Search** — real YouTube search results in horizontal layout with scroll-based load-more and cleaner toolbar search presentation
- **Subscriptions** — real subscription feed when signed in via OAuth with top-up from subscribed-channel uploads when sparse
- **Library** — signed-in playlists, your videos, liked videos, downloads, and **Watch Later** (see below for details)
- **Watch Page Actions** — subscribe/unsubscribe with live state, like/dislike with RYD counts, Watch Later (see below), in-app comment posting
- **Downloads** — yt-dlp integration for offline video downloads with per-video resolution picker (supports 1080p+ via adaptive formats), progress tracking, offline playback
- **Extensions** — SponsorBlock (privacy-preserving hash-based), Return YouTube Dislike, DeArrow; all auto-refresh every 5 minutes, toggleable in Settings
- **Authentication** — Google OAuth 2.0 device code flow with Keychain token storage, auto-refresh, quick setup in account popover, and clear error guidance (requires your own TV/limited-input OAuth client credentials)
- **Channel Pages** — full channel view with avatar, subscriber count, video grid, and "Open on YouTube" action
- **Settings** — extensions toggles, playback settings, update checking, support links

### Watch Later — Important Notes

**GlassTube uses a custom "GlassTube Watch Later" playlist as a fallback for saving videos to Watch Later.**

- When possible, Watch Later saves use YouTube's internal Innertube API (`browse/edit_playlist`) to add/remove videos from your real Watch Later queue.
- If YouTube rejects the action (due to authentication, scope, or API limitations), GlassTube falls back to a local "GlassTube Watch Later" playlist stored on your device.
- **A disclaimer is shown in the UI when the fallback playlist is used.**
- The fallback playlist is not synced with your YouTube account and will not appear on youtube.com or other YouTube apps.
- This approach ensures you always have a working Watch Later queue, but with clear separation between your real YouTube Watch Later and the local fallback.

**Why?**

Due to Google restrictions, the YouTube Data API has blocked writes to the official Watch Later playlist (`playlistItems.insert` to `WL`) since 2016. GlassTube attempts to use the same internal API as YouTube's web client, but if this fails (e.g., due to auth or scope issues), the app provides a local fallback so you never lose the ability to "save for later".

**How it works:**

- If Watch Later is available, videos are added/removed via the Innertube API.
- If not, videos are added/removed from the local "GlassTube Watch Later" playlist, with a clear disclaimer in the UI.


## OAuth Setup (Required for Sign-In)

Google now rejects previously shared/default OAuth clients for this flow, so sign-in works only with your own credentials.

Critical requirement while your app is in Testing mode:

- Login will fail with `Error 403: access_denied` unless the exact Google account you are signing in with is added under OAuth consent screen > Audience > Test users.

### Step-by-step setup (recommended order)

1. In Google Cloud Console, create/select your `GlassTube` project.
2. Enable `YouTube Data API v3` for that same project.
3. Create OAuth credentials with application type **TVs and Limited Input devices**.
4. Copy the generated Client ID and Client Secret.
5. In GlassTube, open **Settings > Authentication** and paste/save Client ID + Client Secret.
6. In Google Cloud Console, open **OAuth consent screen > Audience**.
7. In **Test users**, add the exact email you will use to sign in.
8. Wait about 1-5 minutes for Google to propagate changes.
9. In GlassTube, click **Sign In with Google** and enter the shown user code at Google verification URL.

### Pre-sign-in checklist

- Client type is **TVs and Limited Input devices**.
- Client ID and Secret are saved in GlassTube.
- Same Google sign-in email is present in Audience > Test users.

Troubleshooting:

- `access_denied`: OAuth app is in Testing mode and your sign-in email is not yet in **Audience > Test users**, or changes have not propagated yet.
- `invalid_client` or `unauthorized_client`: client ID is wrong or not a **TVs and Limited Input devices** client.
- `restricted_client`: Google rejected the client (commonly seen with shared/default clients).
- `org_internal`: OAuth consent screen is set to internal organization users only.
- `slow_down`: temporary polling throttle from Google; wait and retry.

Reference docs:

- [OAuth 2.0 for TV and Limited-Input Device Applications](https://developers.google.com/identity/protocols/oauth2/limited-input-device#creatingcred)
- [YouTube OAuth 2.0 for Devices](https://developers.google.com/youtube/v3/guides/auth/devices)
- [OAuth 2.0 for iOS and Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app) (Google platform guidance and related OAuth error references)


## Feed Personalization Notes

- GlassTube requests `youtube.readonly` and `youtube` — the only YouTube scopes Google's TV/Limited-Input device flow supports. Data API write actions that require `youtube.force-ssl` (comment posting, video likes/dislikes, subscribe/unsubscribe) cannot be granted through this flow; use YouTube in a browser for those actions.
- When GlassTube bumps its internal `oauthScopeVersion`, existing users are automatically signed out on next launch so Google can reissue tokens with the new scope set. Sign in again when prompted.
- **Watch Later saves:** GlassTube first tries to use the Innertube API (`browse/edit_playlist`) to add/remove videos from your official Watch Later playlist. If this fails, the app falls back to a local "GlassTube Watch Later" playlist with a clear disclaimer. The fallback playlist is not synced with your YouTube account and is only available in GlassTube.
- If Google returns "insufficient authentication scopes", sign out in GlassTube and sign in again to refresh token scopes.
- Signed-in Home results can still differ from the official YouTube app/web experience.
- Google documents `activities.list` with `home=true` as deprecated and indicates it may return results similar to logged-out home.

## Home Feed Troubleshooting

- If Home shows an error with quota language, your Google project likely exhausted daily YouTube Data API units.
- Default quota is 10,000 units/day and resets at midnight Pacific Time.
- If Home fails while signed in, GlassTube now falls back to anonymous discovery queries so the surface can still load videos.
- If failures persist, re-authenticate in Settings > Authentication and retry.

Relevant docs:

- [YouTube Data API activities.list](https://developers.google.com/youtube/v3/docs/activities/list)
- [YouTube Data API Reference](https://developers.google.com/youtube/v3/docs)

## Requirements

- macOS 26+ (Tahoe) for Liquid Glass APIs
- Xcode 26+
- Apple Silicon recommended for hardware AV1 decode
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) at `/opt/homebrew/bin/yt-dlp` for downloads

## Building

Open `GlassTube.xcodeproj` in Xcode and run, or:

```bash
xcodebuild -project GlassTube.xcodeproj -scheme GlassTube -destination 'platform=macOS' build
```

## Keyboard Shortcuts

| Key | Action |
| --- | --- |
| Space / K | Play/Pause |
| Left / Right | Seek -/+ 5s |
| Up / Down | Volume -/+ 5% |
| M | Mute/Unmute |
| Cmd+Shift+T | Test YouTube API |

## Tech Stack

- **SwiftUI** with Liquid Glass (`GlassEffectContainer`, `.glassEffect()`)
- **AVFoundation / AVKit** for hardware-accelerated playback
- **Swift Concurrency** (async/await) for all API calls
- **YouTube Innertube API** for video data, search, and streaming
- **Google OAuth 2.0** device code flow for authentication
- **yt-dlp** for video downloads
- **SponsorBlock / RYD / DeArrow** APIs for third-party extensions
- **CryptoKit** for SHA256 hashing (SponsorBlock privacy)
- **macOS Keychain** for secure token storage

## Privacy

- No tracking or analytics
- SponsorBlock uses hash-based lookups (your video IDs are never sent in full)
- OAuth tokens stored in macOS Keychain, never in plaintext
- App sandbox disabled only for yt-dlp subprocess execution

## Credits

GlassTube draws inspiration and implementation details from several open-source projects:

- [YouTube.js](https://github.com/LuanRT/YouTube.js) — JavaScript client for YouTube's private Innertube API. Used as a reference for Innertube endpoints, playlist editing, and client context handling.
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — Command-line YouTube downloader. Used for download integration and as a reference for stream extraction and error handling.
- [NewPipe](https://github.com/TeamNewPipe/NewPipe) — Android YouTube client. Referenced for playlist management and fallback strategies.
- [SponsorBlock](https://github.com/ajayyy/SponsorBlock) — API and segment database for ad-skipping. Used for privacy-preserving segment fetching.

If you use or distribute this app, please credit these projects and their authors.

## License

GlassTube is released under the [MIT License](LICENSE).

GlassTube is an independent third-party client and is not affiliated with, endorsed by, or sponsored by YouTube or Google LLC. YouTube is a trademark of Google LLC.
