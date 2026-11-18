<h1>
  <img src="assets/plezy.png" alt="Plezy Retrowave logo" height="24" style="vertical-align: middle;" />
  Plezy Retrowave
</h1>

A Windows-focused fork of [Plezy](https://github.com/edde746/plezy) with a retrowave look, a Ratings & links row on every movie and show, a restyled player and a **YouTube tab** for your subscriptions with its own retrowave player. Everything Plezy does still works; this fork only adds to it.

Current version: **0.6.1**.

<p>
  <a href="#whats-new-in-061">What's new</a> ·
  <a href="#download">Download</a> ·
  <a href="#what-this-fork-adds">What this fork adds</a> ·
  <a href="#youtube">YouTube</a> ·
  <a href="https://github.com/edde746/plezy">Upstream Plezy</a> ·
  <a href="LICENSE">License</a>
</p>

## What's new in 0.6.1

#### Mini player
- A **Mini player** button in the Plex player and the YouTube player shrinks the video into a bar along the bottom of the app, so you can keep browsing while it plays.
- The bar has the live video, title, back 10 s, play/pause, forward 30 s, next, volume, a button to open the full player again and a **Stop** button that ends playback and closes the player.
- **Back** (back arrow, Escape or the Back key) also minimizes the player instead of closing it. Turn it off under Settings › Playback › "Back opens the mini player".
- Clicking the small video or the title opens the full player again. Pages opened while it was minimized are closed when you do.
- Playing something else opens it in the full player; starting a YouTube video stops a minimized Plex video and the other way round.

#### Picture
- The video always keeps its aspect ratio: the stretching fill mode is gone. The fit button switches between **Fit** and **Fit height**. Fit height crops black bars baked into the video and fills the screen's height with the picture itself, never cutting anything off at the top or bottom.
- Optional **Fill the screen when letterboxed** (Settings › Playback): crops black bars baked into a video in Fit mode as well.

#### HDR
- **HDR brightness boost** slider (Settings › Playback and the player's own settings, under the HDR switch; Windows): an extra lift for the midtones of HDR videos that look too dark. Off keeps the picture as mastered, HDR stays on at every setting, and changes apply right away.
- HDR videos use a brighter tone curve by default (`tone-mapping=bt.2446a`, `hdr-peak-percentile=99.5`, `hdr-contrast-recovery=0.3`). Lines in your own mpv config still win.

#### Player
- Clicking the video plays or pauses it; double-click still toggles fullscreen. Turn it off under Settings › Playback.
- Play button down to 38 px in the Plex and YouTube players.
- Fixed: the page background covered the YouTube video.

## What's new in 0.6.0

#### Rebuilt YouTube player
- The player is now a native WebView2 window beneath the app's interface, the same way the Plex player (mpv) works. This replaces the old frame-capture bridge, which caused black video (with audio still playing) when the app was out of focus, on another monitor, while side panels opened or when a watchlist moved to the next video.
- One shared WebView for all videos, capped at 60 fps and suspended when the player is closed, for lower memory and CPU use.
- Recovers on its own after sleep or hibernation, after a stall, when play does nothing, or if the WebView process crashes.
- Shows the video thumbnail while a video loads instead of a black screen.

#### YouTube
- A home button on every YouTube sub-page leads straight back to the subscriptions page, and the watchlist has a back button.
- Upload time is shown as "2h ago" with the same spacing as the view count.

#### Retrowave look
- Every colour comes from one palette taken from a retrowave night landscape: night purple, violet, magenta and cyan.
- A muted background fade on every page.
- Windows title bar and window border in the same night purple (Windows 11).
- New cyan, violet and magenta app icon, installer icon and startup logo.
- Smaller violet play button without the glow, in the Plex and YouTube players.
- The volume slider uses the same fade as the timeline, everywhere.

#### Libraries
- Episodes show the series poster in libraries and rows by default. Episode thumbnails appear in a season's episode list. Existing installs keep their setting: Settings › Appearance › Episode poster.

#### Installer
- Always shows the install folder page, so you can choose where it installs.

## Download

Get the latest Windows build from the [Releases page](https://github.com/thetwistedchi/plezy/releases):

| File | What it is |
| --- | --- |
| `plezy-retrowave-installer.exe` | Installer (x64). Installs as **Plezy Retrowave**, next to a regular Plezy install. |
| `plezy-retrowave-x64-portable.7z` | Portable build, unzip and run `plezy.exe`. |

The builds are not code-signed, so Windows SmartScreen warns on first launch: click **More info**, then **Run anyway**.

Plezy Retrowave and upstream Plezy share the same settings and sign-ins on one PC.

## What this fork adds

### Retrowave theme

- New free **Retrowave** theme (Settings › Appearance › Theme). Every colour comes from one palette taken from a retrowave night landscape: night purple, violet, magenta and cyan.
- A muted background fade on every page, from night purple at the top through dark blue-violet to a hint of magenta.
- The Windows title bar and window border in the same night purple (Windows 11).
- Retrowave app icon on the window, taskbar, Start menu, installer and login screen, and a cyan-violet-magenta startup logo.
- Libraries and rows show the **series poster** for episodes by default. Episode thumbnails appear in a season's episode list. Existing installs keep their setting (Settings › Appearance › Episode poster).

### Ratings & links on the details page

- A **Ratings & links** row above the overview of every movie and show, one card per site. The whole card opens the site:
  - **Letterboxd** (movies): average rating out of 5 and vote count
  - **Trakt**: community rating and votes, linking straight to the title
  - **IMDb**, **Rotten Tomatoes** (critics and audience) and **TMDB**
- Scores from your Plex server or connected trackers (Trakt, MDBList) are used first. Missing Letterboxd and Trakt scores are fetched directly and cached for 24 hours.
- The **Rate** sheet gets a **Rate on Letterboxd** row that opens the film's page (Letterboxd's API is by request only).
- **Studio, Producer and Director** shown under the overview.

### Player

With the Retrowave theme:

- Compact violet play/pause button
- Timeline fades cyan to magenta up to the playhead, and the volume slider uses the same fade
- Neon "Skip intro / credits" button
- Active controls and playback-settings highlights in purple instead of amber

In every theme:

- **4K / HDR badge** in the bottom bar: resolution (4K, 1440p, 1080p, 720p, SD) and dynamic range (DV, HDR10, HLG). Hidden while transcoding.

### Watch Together

- The in-player session pill shows **HOST** for the host. A guest in a host-only room sees a lock and the host's name.
- Hovering the dimmed play button tells guests that the host controls playback.

## YouTube

A **YouTube** tab in the sidebar with the newest videos from the channels you follow, played in the app with the retrowave controls. **How it works** (the **?** in the YouTube tab) explains every setup step in the app.

### Two ways to use it

| | Without an account | With Google sign-in (optional) |
| --- | --- | --- |
| Channels | Add by link or @handle, or import Google Takeout's `subscriptions.csv` | Your subscriptions are imported automatically (and combined with the ones you add) |
| Videos | From YouTube's public RSS feeds, no quota | Same, plus video lengths and premiere detection |
| Player, SponsorBlock, DeArrow, chapters, watchlist | ✓ | ✓ |
| YouTube Premium (no ads) | ✓ via the player sign-in | ✓ |
| Comments, like / dislike | – | ✓ (read and write) |
| Channel pages | Newest 15 videos | All uploads |

Google sign-in needs a free Google Cloud project with your own OAuth client (Desktop app); the in-app guide walks through it. The sign-in is stored encrypted with Windows (DPAPI).

### Subscriptions view

- Sort by **Newest** or **Most relevant** (channels you watch, videos doing unusually well, freshness)
- Filter **All / Unwatched / Continue**; Shorts and premieres hidden by default
- **+** on a thumbnail adds it to the **watchlist**, **⋮** (or right-click) to open the channel, mark it as favourite, hide the video or hide the whole channel
- Progress bars on thumbnails, DeArrow titles and thumbnails instead of clickbait
- Windows notifications for new videos from favourite channels

### Player

- Embedded YouTube player (WebView2) with YouTube's own controls hidden and the retrowave controls on top
- Gradient timeline with chapter gaps, chapter names and storyboard previews on hover
- Quality with YouTube's names (1080p60, 2160p60 HDR), speed from 0.25× to 2× including 1.1× and 1.2× (remembered)
- Captions: creator and auto-generated tracks, auto-translate, preferred language in settings
- Audio language: switch between audio tracks; the original audio is preferred over AI dubs
- **SponsorBlock**: auto-skip with undo, or a neon skip button, per category; segments and the highlight on the timeline
- Resumes where you stopped; the watchlist plays in order and drops finished videos
- Side panels: watchlist (reorder, add from your feed), comments, more from the channel; channel pages
- Like / dislike with **Return YouTube Dislike** counts, share link (with timestamp), sleep timer, fullscreen
- Shortcuts: Space/K, J/L or arrows, ↑/↓, M, F, C, N, 0–9, `<` `>`, `,` `.`
- Discord status, using Plezy's existing Discord setting
- Every button can be hidden in Settings › Player buttons

### Known limitations

- Only Windows builds are made and tested for this fork.
- Letterboxd has no public API; its score is read from the film page and may stop working if Letterboxd changes it. The card then still links to the film.
- Trakt scores use Plezy's Trakt app credentials.
- Guest pause requests and chat in Watch Together are not built; they need changes to the Open Watch Party relay.
- YouTube quality, in-between speeds, captions and audio tracks use YouTube's internal player functions and may break if YouTube changes its player. Premium bitrate can't be picked manually.
- Clicks don't reach the embedded video, so YouTube's "Skip ad" button can't be clicked; with Premium there are no ads.
- Videos whose creators disabled embedding open on youtube.com instead.
- SponsorBlock and DeArrow data: [sponsor.ajay.app](https://sponsor.ajay.app) (CC BY-NC-SA 4.0). Dislike estimates: [Return YouTube Dislike](https://returnyoutubedislike.com).

---

# About Plezy (upstream)

Everything below is the upstream Plezy README. Plezy is a modern client for Plex, Jellyfin, and Emby on desktop, mobile, and TV, built with Flutter by [edde746](https://github.com/edde746). Plezy Retrowave is an unofficial fork and is not affiliated with the Plezy project; please report fork-specific issues here, not upstream.

<p>
  <a href="https://plezy.app">Website</a> ·
  <a href="https://plezy.app/#screenshots">Screenshots</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <img src="assets/readme-showcase.webp" alt="Plezy mobile screenshots" width="900" />
</p>

## Download upstream Plezy

<a href='https://apps.apple.com/app/apple-store/id6754315964?pt=128238902&ct=GitHub&mt=8'><img height='60' alt='Download on the App Store' src='./assets/app-store-badge.png'/></a>
<a href='https://play.google.com/store/apps/details?id=com.edde746.plezy&referrer=utm_source%3Dgithub%26utm_campaign%3Dreadme_badge'><img height='60' alt='Get it on Google Play' src='./assets/play-store-badge.png'/></a>
<a href='https://www.amazon.com/gp/product/B0GK65CVS1'><img height='60' alt='Available at the Amazon App Store' src='./assets/amazon-badge.png'/></a>
<a href='https://get.microsoft.com/installer/download/9n5r1s1t68h7?referrer=appbadge&cid=github'><img height='60' alt='Get it from Microsoft' src='./assets/microsoft-badge.png'/></a>

| Platform | Download |
| --- | --- |
| macOS | [DMG (x64, arm64)](https://github.com/edde746/plezy/releases/latest/download/plezy-macos.dmg) |
| Linux x64 | [.deb](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.deb) · [.rpm](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.rpm) · [.pkg.tar.zst](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.pkg.tar.zst) · [.flatpak](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.flatpak) · [.AppImage](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.AppImage) · [portable tar.gz](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.tar.gz) |
| Linux arm64 | [.deb](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.deb) · [.rpm](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.rpm) · [.pkg.tar.zst](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.pkg.tar.zst) · [.flatpak](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.flatpak) · [.AppImage](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.AppImage) · [portable tar.gz](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.tar.gz) |

<details>
<summary>Install with a package manager</summary>

### macOS — Homebrew

```bash
brew install --cask plezy
```

Installed from the old `edde746/plezy` tap? After `brew update` moves Plezy to the official cask, run `brew untap edde746/plezy`.

### Windows — WinGet

```bash
winget install edde746.Plezy
```

### Linux — Flatpak

Install Flatpak with your distribution's package manager, download the bundle for your architecture above, then run:

```bash
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//25.08
flatpak install --user ./plezy-linux-x64.flatpak
flatpak run com.edde746.plezy
```

On arm64, install `plezy-linux-arm64.flatpak`.

<details>
<summary>Sandbox, playback, and folder access</summary>

- Not on Flathub — the remote supplies the Freedesktop runtime only.
- Video playback needs a Wayland session; a pure X11 session shows the interface but cannot create the video plane.
- No host or home filesystem access; app data lives in `~/.var/app/com.edde746.plezy/`. Add host folders through the desktop file chooser portal, and keep download folders writable.
- Network, display, audio, and device access are enabled. `--device=all` (Flatpak 1.14 compatibility) exposes more than GPUs and controllers; session-bus access stays filtered.

</details>

### Linux — AppImage

Download the AppImage for your architecture above, then run:

```bash
chmod +x plezy-linux-x64.AppImage
./plezy-linux-x64.AppImage
```

[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) and AppImageUpdate update it from the latest release. Without FUSE, add `--appimage-extract-and-run`.

### Arch Linux — Pacman

[Distribution package](https://archlinux.org/packages/extra/x86_64/plezy/).

```bash
sudo pacman -S plezy
```

### Fedora / Red Hat — DNF

[Installation instructions](https://github.com/aldobarr/plezy-rpm) · Community repository by [@aldobarr](https://github.com/aldobarr).

### Nix

[Community package](https://search.nixos.org/packages?channel=unstable&query=plezy) maintained by [@mio-19](https://github.com/mio-19) and [@MiniHarinn](https://github.com/MiniHarinn).

### aerynOS — Moss

[Distribution package](https://github.com/aerynOS/recipes/tree/main/p/plezy).

```bash
sudo moss pad plezy
```

</details>

## Features

### <img src="assets/readme_icons/browse.svg" height="20" alt="" align="center" /> Browse & Discover
- Libraries, collections, and playlists — video and audio
- Shuffle a whole movie or TV library
- Discover hub — Continue Watching, Next Up, trending, and recommendations
- Continue Watching shows a title held in several libraries or on several servers once, and asks which copy to play
- Cross-server search across every connected Plex, Jellyfin, and Emby server, including actors and directors
- Filtering, sorting, and alphabetical jump navigation
- Folder browsing and folder playback — home-video libraries open in folder view
- Resolution, HDR/Dolby Vision, and audio-format badges on cards and detail pages
- Favorites and unwatched library filters[^mb]
- Extras — trailers, deleted scenes, behind-the-scenes

### <img src="assets/readme_icons/explore.svg" height="20" alt="" align="center" /> Explore & Requests
- Explore tab — watchlist, trending, popular, and recommendation rows from Plex Discover[^plex], Trakt, MyAnimeList, AniList, Simkl, and Seerr[^connect]
- Search any connected catalog source
- Catalog titles matched back to your own libraries by external ID
- Seerr — request movies and shows with per-season, 4K, and advanced destination options, and see request status inline
- Watchlist sync — add and remove titles on Plex, Trakt, MyAnimeList, AniList, and Simkl from anywhere in the app

### <img src="assets/readme_icons/playback.svg" height="20" alt="" align="center" /> Playback
- Wide codec support (HEVC, AV1, VP9, and more)
- HDR and Dolby Vision[^hdr]
- Direct play, or transcode presets from 240p/320 kbps to 1080p/20 Mbps
- Multi-version switching with per-version file details
- Full ASS/SSA subtitles with customizable styling
- Online subtitle search & download[^plex]
- Audio & subtitle choices remembered per title, or follow the server's per-episode selections
- Progress sync and resume
- Auto-play next episode with skip intro / skip credits
- Chapter navigation with thumbnail scrub previews
- Playback speed from 0.25x to 8x, audio sync offset, sleep timer (fixed durations or end of video)
- Video zoom 50-200% with pinch, presets, and hotkeys
- Audio passthrough[^pass], output channel limit (5.1 or stereo, with center-channel boost), and loudness normalization
- File Info sheet — every version, file, and stream the server reports
- Ambient lighting and GLSL shader presets[^mpv]
- Picture-in-Picture[^pip]
- Refresh-rate matching[^rrm]
- External player launch (VLC, MX Player, etc.) with progress sync back[^android]

### <img src="assets/readme_icons/music.svg" height="20" alt="" align="center" /> Music
- Music libraries — artist, album, and track browsing with square artwork
- Album and artist screens with play, shuffle, and Instant Mix
- Gapless playback with a full play queue — reorder, remove, play next, add to queue
- Now Playing with synced lyrics[^lyrics], persistent mini-player, and sleep timer
- Background playback with lock-screen, media-key, and notification controls[^bgaudio]
- Offline playback of downloaded albums and tracks
- Streaming quality presets — Original, 320, 192, or 128 kbps

### <img src="assets/readme_icons/live-tv.svg" height="20" alt="" align="center" /> Live TV & DVR
- Live TV channel browsing, tuning, and favorites
- EPG guide with What's On and per-show schedules
- DVR recording rules, scheduled recordings, and a rememberable recording target library[^plex]
- Multi-server Live TV support where available

### <img src="assets/readme_icons/downloads.svg" height="20" alt="" align="center" /> Downloads & Offline
- Download movies, shows, and music for offline playback[^dl]
- Background queue with pause / resume
- Sync rules for automatic downloads, with per-show "Include Specials"
- Offline browsing with watch state sync-back on reconnect

### <img src="assets/readme_icons/watch-together.svg" height="20" alt="" align="center" /> Watch Together
- Rooms on [Open Watch Party](https://openwatch.party) — share a six-character code; friends join from Plezy or another Open Watch Party app
- Everyone plays their own copy from their own server — Plex, Jellyfin, or Emby — matched by catalogue IDs, with a picker when several copies fit
- Synchronized play / pause / seek, host or shared control, room lock, and host handoff
- Public relays by default, or point Plezy at your own self-hosted relay

### <img src="assets/readme_icons/integrations.svg" height="20" alt="" align="center" /> Integrations
- Discord Rich Presence[^desktop]
- Trakt, MyAnimeList, AniList, and Simkl — ratings, watched sync, and real-time scrobbling[^rt]
- Scores from connected trackers on detail pages — Trakt, Simkl, MyAnimeList, and AniList, plus Rotten Tomatoes, Metacritic, Letterboxd, IMDb, and TMDB through MDBList
- Plezy Remote — control desktop and TV from mobile
- Watch Next row and tvOS Top Shelf[^shelf]
- [`plezy://` links](#plezy-links) to open a profile, play a title, or tune a channel from Home Assistant, launchers, or an NFC tag; any movie, show, or episode menu shows its link[^links]

### <img src="assets/readme_icons/customization.svg" height="20" alt="" align="center" /> Platform & Customization
- Desktop, mobile, and TV — full D-pad, keyboard, and gamepad support
- Multiple servers at once — Plex, Jellyfin, and Emby side by side
- Profiles with per-profile downloads, watch state, and settings; Plex Home switching with PIN
- Jellyfin and Emby local-server discovery and multiple URLs per server; Quick Connect sign-in[^jf]
- TV layout options — corner spotlight backdrop, full-card artwork, and Force TV mode on desktop
- Customizable keyboard shortcuts[^desktop]
- Metadata and artwork editing
- Settings import/export
- Localized in English plus 21 translations

[^jf]: Jellyfin only.
[^mb]: Jellyfin and Emby only.
[^plex]: Plex only.
[^connect]: Requires connecting the service under Settings > Services.
[^hdr]: In-app HDR toggle on Windows, macOS, iOS, tvOS, and Linux — Linux needs a colour-managed Wayland compositor. Dolby Vision on Android, macOS, and Apple TV.
[^pass]: Desktop, Android TV, and Apple TV.
[^mpv]: Requires the mpv player backend — Android defaults to ExoPlayer. Not applied to Dolby Vision on Apple platforms.
[^pip]: Android, iOS, and macOS — not on Android TV or Apple TV.
[^rrm]: Windows, Android, and tvOS.
[^android]: Progress sync on Android.
[^lyrics]: Where your server provides lyrics.
[^bgaudio]: tvOS pauses music when the app is backgrounded.
[^dl]: Not available on tvOS.
[^desktop]: Desktop only.
[^rt]: Real-time scrobbling on Trakt and Simkl; MyAnimeList and AniList update on completion.
[^shelf]: Android TV / Fire TV and tvOS.
[^links]: Android, iOS, macOS, and tvOS.

## plezy:// links

Links start Plezy from outside the app. Any link may add `profile=<profile>`: a profile id, a Plex Home user UUID, or a display name (ignoring case; it must match one profile). Plezy switches to that profile first, and a protected profile still asks for its PIN. A link replaces whatever is playing.

| Link | Does |
|---|---|
| `plezy://open` | Opens Plezy |
| `plezy://play?server=<server>&id=<item>` | Plays one item on one server, any backend |
| `plezy://play?type=movie\|show&tmdb=<n>` | Plays a title from whichever server has it. Use `tmdb`, `tvdb`, `imdb=tt<n>`, or `plex=<hash>` (the Plex GUID without `plex://movie/`) |
| `plezy://live?channel=<channel>` | Tunes a Live TV channel by key, number, or call sign. Optional `server=<server>` and `start=beginning\|live` |

For a show, `mode=next` (the default) plays the next episode to watch, and `mode=shuffle` plays the show shuffled. The menu of any movie, show, or episode has **Show link**, and each profile's menu in **Switch Profile** has **Show profile link**. Both show the link as text and a QR code.

```sh
# Android / Android TV, over adb (Home Assistant: remote.turn_on with activity: plezy://...)
adb shell am start -a android.intent.action.VIEW -d "plezy://play?type=show\&tvdb=81189\&profile=Kids"
# macOS
open "plezy://play?type=movie&tmdb=603"
```

On iOS, use the Open URLs action in Shortcuts.

## Building from Source

### Prerequisites
- Flutter SDK 3.47.0+
- A Plex account, or a Jellyfin or Emby server with user credentials

### Setup

```bash
git clone https://github.com/edde746/plezy.git
cd plezy
flutter pub get
scripts/codegen.sh
flutter run
```

<details>
<summary>Code generation</summary>

After modifying model classes or other generated sources:

```bash
scripts/codegen.sh
```

After modifying translations:

```bash
dart run slang
```

</details>

<details>
<summary>Packaging a Flatpak bundle</summary>

Packages an **already fully resolved Linux release bundle** — pinned libmpv and bundled libraries included, not a Flathub source-build manifest. Run it on Linux, on the same architecture as the bundle, after following the bundle preparation steps in [the Linux release workflow](.github/workflows/build.yml): `flutter build linux` alone does not produce all the required bundled libraries.

Install the packaging tools (Debian/Ubuntu shown) plus the native-architecture SDK and runtime:

```bash
sudo apt-get update
sudo apt-get install -y flatpak flatpak-builder imagemagick
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08

BUNDLE_DIR=build/linux/x64/release/bundle
python3 linux/packaging/build-flatpak.py --bundle "$BUNDLE_DIR" --arch x64 --output "$PWD"
```

That writes `plezy-linux-x64.flatpak`, installable with the Flatpak commands above; on arm64, use the prepared arm64 bundle directory and `--arch arm64`. Package from the checkout matching the bundle, since the version comes from `pubspec.yaml`.

Cross-architecture packaging needs native Flatpak tools, a registered binfmt interpreter, and the target SDK/runtime installed with `flatpak install --user --arch=x86_64` (or `aarch64`) — never run Flatpak's namespace tools under emulation. Pass `--arch x64` or `--arch arm64` to the checker and the matching Flatpak architecture to `flatpak run --arch=...`.

Check the installed package against the runtime (not just the SDK), then launch it on a Wayland desktop and exercise streaming, audio, downloads/offline playback, and file chooser portals:

```bash
python3 linux/packaging/check-flatpak.py
```

The check fails on a non-executable entry point or an unresolved bundled ELF dependency. A container without a GPU can use `flatpak run --env=GALLIUM_DRIVER=softpipe com.edde746.plezy` for software-rendered verification; this is not a hardware-decoding or HDR test.

</details>

<details>
<summary>Local checks</summary>

```bash
scripts/ci_checks.sh
```

To install the same pre-commit checks locally:

```bash
scripts/setup_hooks.sh
```

End-to-end tests (Android emulator plus a Dockerized Jellyfin fixture):

```bash
python3 scripts/maestro/run_maestro.py basic
```

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, formatting, tests, and translation guidelines.

## License

Plezy is licensed under [GPL-3.0](LICENSE). The license covers the code, not the Plezy name or logo; forks distributed beyond personal use must follow [TRADEMARKS.md](TRADEMARKS.md).

## Acknowledgments

- Built with [Flutter](https://flutter.dev)
- Supports [Plex Media Server](https://www.plex.tv), [Jellyfin](https://jellyfin.org), and [Emby](https://emby.media)
- Playback powered by [mpv](https://mpv.io) via our [mpv-build](https://github.com/edde746/mpv-build) pipeline (started as a fork of [MPVKit](https://github.com/mpvkit/MPVKit); on Android through its mpv-android library, whose Kotlin/JNI glue descends from [libmpv-android](https://github.com/jarnedemeulemeester/libmpv-android)), Android [ExoPlayer](https://developer.android.com/media/media3/exoplayer), and [libass-android](https://github.com/peerless2012/libass-android)
