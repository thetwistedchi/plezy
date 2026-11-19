<h1>
  <img src="assets/plezy.png" alt="Plezy Retrowave logo" height="24" style="vertical-align: middle;" />
  Plezy Retrowave
</h1>

> [!WARNING]
> **Disclaimer:** This fork is 100% vibecoded (written entirely with AI assistance) and is intended only for my personal use and preferences. It comes with no support, no guarantees and no promise of stability. Use it at your own risk; for a maintained client, use the original [Plezy](https://github.com/edde746/plezy).

A Windows-focused fork of [Plezy](https://github.com/edde746/plezy) with a retrowave look, a Ratings & links row on every movie and show, a restyled player and a **YouTube tab** for your subscriptions with its own retrowave player. Everything Plezy does still works; this fork only adds to it.

Current version: **0.8.1**.

<p>
  <a href="#whats-new-in-081">What's new</a> ·
  <a href="#download">Download</a> ·
  <a href="#what-this-fork-adds">What this fork adds</a> ·
  <a href="#youtube">YouTube</a> ·
  <a href="https://github.com/edde746/plezy">Upstream Plezy</a> ·
  <a href="LICENSE">License</a>
</p>

## What's new in 0.8.1
#### Android TV (e.g. NVIDIA Shield)
- The Android app is now called **Plezy Retrowave**, with a retrowave launcher icon and TV home-screen banner.
- It installs as its own app (`com.thetwistedchi.plezyretrowave`), so it sits next to the official Plezy instead of replacing it. Coming from an earlier Android build of this fork, sign in once again.
- The quality and language pills under posters now also show on Android TV, and their switch is in Settings › Appearance there too.
- Hide watched per Home row works on TV: long-press (Select held) a title in a Home row and pick **Hide watched in this row** or **Show watched in this row**. A row emptied this way stays visible so it can be shown again.
- The Home spotlight on TV shows the rating median (★) next to the other scores.
- The trailer button searches YouTube and opens the trailer in the device's YouTube app. The server's own trailer is the fallback.
- **Remember tracks per title** is listed in the playback settings on every platform.
- Library filters (quick chips, active pills, saved sets, Surprise me), Play from start, Similar in your library and Startup library already work on Android TV.

#### All platforms
- New installs start with the Retrowave theme on every platform (Android TV used to start with OLED). An already chosen theme is kept.
- Manage Libraries marks the focused library clearly: it is tinted and outlined in the accent colour, more strongly while the row itself has focus.
- Smoother browsing: the background lookups for poster pills and rating medians use a lighter server request that skips chapters and markers, and run one at a time on TV devices. The page background is no longer repainted while scrolling. Quick filters and **Similar in your library** remember what they looked up per library, so reopening a library or another details page needs fewer requests.
- Hide watched per Home row is also in the right-click menu of a title in that row.
- The hover preview no longer blocks scrolling with the mouse wheel.

## What's new in 0.8.0
Everything new since 0.7.1.

#### Library filters
- **Quick filters** next to Filters and Sort toggle common filters with one click: **Unwatched**, **4K**, **HDR**, **Audio** in the app's language (e.g. `Audio: EN`) and **Added recently** (last 30 days). Each chip only appears when the library's server offers that filter, and it sets the same filter the Filters panel shows.
- **Active filters as pills**: a second row under the bar lists every active filter (e.g. `Genre: Action`). Clicking a pill removes that filter.
- **Saved filter sets**: the **Saved** chip stores the current filters and sort under a name, per library. Picking a set applies it again; sets can be deleted from the same menu.
- **Surprise me** opens a random title from the current filtered list.
- The chip bar scrolls sideways when it no longer fits, and follows the D-pad.

#### Libraries
- Switching back to a library returns to the scroll position it was left at.
- Settings › General › **Startup library** picks the library the Libraries section opens on after starting the app. "Last used" keeps the previous behaviour.

#### Home
- Each Home row has an eye toggle next to its title (shown on hover, or always while active) that hides titles already watched in that row. It follows the same watched state as the poster check mark, including titles marked watched in the app. The choice is kept per row.

#### Posters
- Resting the mouse on a poster shows a preview with the year, runtime, genres, the rating median and the plot when the list includes one (seasons and some episodes have none). It uses only what the list already loaded, so it makes no extra requests.
- Settings › Appearance has a switch for the preview and a **Hover preview delay** from 0.25 s to 2.5 s (default 0.65 s).

#### Details page
- When a title can be resumed, a **Play from start** segment (↻) sits next to Resume.
- The trailer button searches YouTube for the trailer and plays it in the YouTube player, so it works with the mini player and the queue. When nothing is found, the server's own trailer plays. Without the in-app YouTube player, the server's trailer is used as before.
- A new row **Similar in your library** lists up to 20 titles from the same library that share genres with the title, ranked by how many genres they share and then by their score.

#### Player
- The audio track, subtitle track and zoom mode picked for a movie or series are remembered for that title. A series shares one choice across its episodes, matched by language, so another episode's file picks the same language. Can be turned off under Settings › Playback › **Remember tracks per title**.

#### YouTube
- **Channel groups** on the subscriptions page: **New group** creates a named set of channels (e.g. Music, Tech). Selecting a group shows only videos from its channels. Right-click or long-press a group to rename, change or delete it.
- **Suggest groups** proposes one group per YouTube category (Music, Gaming, Science & Technology and so on), based on each channel's most common video category, and creates the ones picked. A suggestion with the name of an existing group adds its channels to that group. The category comes with the video details the app already loads for a signed-in account, so it costs no extra requests. Channels followed without a Google account have no category and are picked by hand.
- When editing a group, channels are sorted by category and show it, and a category chip ticks all its channels at once.
- YouTube can be chosen as the startup section under Settings › General.

#### General
- Pressing **?** anywhere outside a text field shows all keyboard shortcuts, including the player keys as currently set.
- The README now states that this fork is built with AI assistance for personal use, with no support or guarantees.

## What's new in 0.7.1
#### Posters
- The rating median now appears on far more posters. Library lists carry at most two scores per title, often only the Tomatometer, which the median leaves out. Posters therefore use the full median once a title's details page was opened, and otherwise fetch the title's scores from its own Plex server in the background, a few at a time. With an MDBList key, MDBList fills in when the server has too few scores. Medians are kept on disk, so each title is looked up only once every two weeks.
- Seasons and episodes in Home rows (such as Recently added) show their series' median.
- New look for poster badges: the rating (★), the unwatched-episode count and the watched check mark are small dark purple pills with a muted neon rim and tinted text, centred exactly.
- Under each poster a row of pills shows the resolution, HDR and the audio languages (e.g. `4K` `HDR` `DE · EN`; more than two languages as `+2`). Languages come from the title's own Plex server, looked up once per title and kept for a month; series use their first episode. Can be turned off under Settings › Appearance.
- Row headings with their icons and arrows, and card titles, use a periwinkle blue that no other text uses.

#### YouTube
- A **Continue where you left off** card at the top of the subscriptions page resumes the last unfinished video with one click, at the position it stopped. Dismissing it hides that video.
- The same video appears as the first card of Home's **Continue watching** row, in poster size with a YouTube mark and its progress. Right-click hides it.
- The **⋮** menu of a video has **Copy link**, and **Copy link at …** for a video watched part way, which starts at the saved position.
- In the player's **More from this channel** panel, each video has a button that adds it to the queue and the watchlist; queued videos show a check.

#### Other themes
- The Windows title bar, the mini player bar, the YouTube pages and player panels, and the rating badge on posters follow the active theme. The retrowave colours stay in the Retrowave theme.

## What's new in 0.7.0
#### Rating median
- Movie and series posters show the median of their scores in the top left corner, on a 0–100 scale. It uses only the scores Plex already sends with the library, so scrolling makes no extra requests.
- The details page shows a **Median** card after Ratings & links, with the number of sources it is based on.
- Every score is converted to 0–100 first (IMDb 7.8/10 → 78, Letterboxd 3.9/5 → 78). The Tomatometer is left out: it is the share of positive reviews, not an average score.

#### More rating sources
- New section **Settings › Services › Rating sources**:
  - **MDBList**: one request for IMDb, TMDB, Trakt, Letterboxd, Rotten Tomatoes, Metacritic and MyAnimeList. Needs a free API key from mdblist.com.
  - **OMDb**: IMDb, Tomatometer and Metascore when MDBList has none. Needs a free API key from omdbapi.com.
  - **MyAnimeList (Jikan)**: anime scores, no key needed.
- New cards in Ratings & links: **Metacritic**, **MyAnimeList** and the Rotten Tomatoes audience score.
- API keys are stored encrypted, are not part of settings exports, and are tested when saved. A key that a site rejects shows as "Key rejected".
- Without keys, or when a site does not answer, Letterboxd and Trakt scores are still fetched directly, now in parallel. A site that failed is asked again after 15 minutes instead of the next day.

#### Letterbox detection
- Black bars are only cropped when they are about equally high at the top and bottom (or left and right), so dark scenes no longer cause wrong crops.
- A second check a few minutes into a film can only shrink the crop, correcting a too large first guess.
- The snapshots used for detection are taken at low quality, which avoids hitches on 4K HDR.

#### Mini player
- Keyboard media keys control a minimized YouTube video.
- When a video ends while minimized and nothing plays next, the mini player closes on its own.

#### Performance
- YouTube playback positions are kept in their own file and saved every 30 seconds and on pause, instead of rewriting the settings file every 5 seconds.
- The YouTube player is fully released after 10 minutes without use, freeing its memory. The next YouTube video then takes a second or two longer to start.
- Rating results are cached for about the last 300 titles.

## What's new in 0.6.1

#### Mini player
- A **Mini player** button in the Plex player and the YouTube player shrinks the video into a bar along the bottom of the app; browsing continues while it plays.
- The bar has the live video, title, back 10 s, play/pause, forward 30 s, next, volume, a button to open the full player again and a **Stop** button that ends playback and closes the player.
- **Back** (back arrow, Escape or the Back key) also minimizes the player instead of closing it. Can be turned off under Settings › Playback › "Back opens the mini player".
- Clicking the small video or the title opens the full player again. Pages opened while it was minimized are closed in the process.
- Playing something else opens it in the full player; starting a YouTube video stops a minimized Plex video and the other way round.

#### Picture
- The video always keeps its aspect ratio: the stretching fill mode is gone. The fit button switches between **Fit** and **Fit height**. Fit height crops black bars baked into the video and fills the screen's height with the picture itself, never cutting anything off at the top or bottom.
- Optional **Fill the screen when letterboxed** (Settings › Playback): crops black bars baked into a video in Fit mode as well.

#### HDR
- **HDR brightness boost** slider (Settings › Playback and the player's own settings, under the HDR switch; Windows): an extra lift for the midtones of HDR videos that look too dark. Off keeps the picture as mastered, HDR stays on at every setting, and changes apply right away.
- HDR videos use a brighter tone curve by default (`tone-mapping=bt.2446a`, `hdr-peak-percentile=99.5`, `hdr-contrast-recovery=0.3`). Lines in a custom mpv config still take precedence.

#### Player
- Clicking the video plays or pauses it; double-click still toggles fullscreen. Can be turned off under Settings › Playback.
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
- The installer always shows the install folder page, so the install location can be chosen.

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
