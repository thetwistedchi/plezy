## Plezy Retrowave 0.6.0

### Mini player
- A **Mini player** button in the Plex player and the YouTube player shrinks the video into a bar along the bottom of the app, so you can keep browsing while it plays.
- The bar has the live video, title, back 10 s, play/pause, forward 30 s, next, volume, a button to open the full player again and a **Stop** button that ends playback and closes the player.
- **Back** (back arrow, Escape or the Back key) also minimizes the player instead of closing it. Turn it off under Settings › Playback › "Back opens the mini player".
- Clicking the small video or the title opens the full player again. Pages opened while it was minimized are closed when you do.
- Playing something else opens it in the full player; starting a YouTube video stops a minimized Plex video and the other way round.

### Rebuilt YouTube player
- The player is now a native WebView2 window beneath the app's interface, the same way the Plex player (mpv) works. This replaces the old frame-capture bridge, which caused black video (with audio still playing) when the app was out of focus, on another monitor, while side panels opened or when a watchlist moved to the next video.
- One shared WebView for all videos, capped at 60 fps and suspended when the player is closed, for lower memory and CPU use.
- Recovers on its own after sleep or hibernation, after a stall, when play does nothing, or if the WebView process crashes.
- Shows the video thumbnail while a video loads instead of a black screen.

### YouTube
- A home button on every YouTube sub-page leads straight back to the subscriptions page, and the watchlist has a back button.
- Upload time is shown as "2h ago" with the same spacing as the view count.

### Plex player
- Clicking the video plays or pauses it (double-click still toggles fullscreen). Can be turned off under Settings › Playback.

### Retrowave look
- Every colour comes from one palette taken from a retrowave night landscape: night purple, violet, magenta and cyan.
- A muted background fade on every page.
- Windows title bar and window border in the same night purple (Windows 11).
- New cyan, violet and magenta app icon, installer icon and startup logo.
- Smaller violet play button (38 px) without the glow, in the Plex and YouTube players.
- The volume slider uses the same fade as the timeline, everywhere.

### Libraries
- Episodes show the series poster in libraries and rows by default. Episode thumbnails appear in a season's episode list. Existing installs keep their setting: Settings › Appearance › Episode poster.

### Installer
- Always shows the install folder page, so you can choose where it installs.
