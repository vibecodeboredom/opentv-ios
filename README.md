# OpenTV for iOS

Free, open-source native IPTV player for iPhone and iPad — the iOS companion to
[OpenTV for Android TV](https://github.com/vibecodeboredom/opentv).
M3U playlists + XMLTV programme guide, with a clean native player.

MIT licensed. Built with SwiftUI + AVPlayer. No account, no ads, no tracking.

## Features

- **M3U playlists** — add by URL or import an `.m3u` file; multiple playlists with on/off toggles; swipe to remove
- **XMLTV guide (EPG)** — fetched and cached locally in SQLite, refreshed in the background (default guide: `https://i.mjh.nz/PlutoTV/us.xml`)
- **Guide view** — what's on now, programmes from 4 hours back to 12 hours ahead; tap a channel to play
- **Channels** — search, groups from the playlist, now-playing info, pull to refresh
- **Favorites** — star any channel, dedicated Favorites tab
- **Player** — full-screen AVPlayer (HLS), resumes your last-watched channel on launch, retries a dead stream 3 times before showing a clear error
- **Sample playlist** — one-tap PlutoTV (US) playlist in Settings to get started

No parental controls / PIN lock by design.

## Install on iPhone

The IPA is unsigned — sideload it with your free Apple ID:

1. Download `OpenTV-1.0.0.ipa` from the
   [latest release](https://github.com/vibecodeboredom/opentv-ios/releases/tag/v1.0.0).
2. Install it with **AltStore** (AltStore PAL / AltServer) or **Sideloadly**.
   Both sign the app with your Apple ID, so it installs like a normal app.
3. Open OpenTV, add a playlist in Settings (or tap the PlutoTV sample), and watch.

Note: apps sideloaded with a free Apple ID expire after 7 days — just
re-sign/reinstall with AltStore or Sideloadly to keep using it.

## Build from source

Requires Xcode 16+ on macOS, iOS 16+ target.

```sh
xcodebuild -project OpenTV.xcodeproj -scheme OpenTV \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

Or open `OpenTV.xcodeproj` in Xcode and build with your own signing.

## License

MIT — see [LICENSE](LICENSE).
