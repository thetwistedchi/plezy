## Plezy Retrowave 0.6.0

### Rebuilt YouTube player
- The player is now a native WebView2 window beneath the app's interface, the same way the Plex player (mpv) works. This replaces the old frame-capture bridge, which caused black video (with audio still playing) when the app was out of focus, on another monitor, while side panels opened or when a watchlist moved to the next video.
- One shared WebView for all videos, capped at 60 fps and suspended when the player is closed, for lower memory and CPU use.
- Recovers on its own after sleep or hibernation, after a stall, when play does nothing, or if the WebView process crashes.
- Shows the video thumbnail while a video loads instead of a black screen.

### YouTube
- A home button on every YouTube sub-page leads straight back to the subscriptions page, and the watchlist has a back button.
- Upload time is shown as "2h ago" with the same spacing as the view count.

### Retrowave look
- Every colour comes from one palette taken from a retrowave night landscape: night purple, violet, magenta and cyan.
- A muted background fade on every page.
- Windows title bar and window border in the same night purple (Windows 11).
- New cyan, violet and magenta app icon, installer icon and startup logo.
- Smaller violet play button without the glow, in the Plex and YouTube players.
- The volume slider uses the same fade as the timeline, everywhere.

### Libraries
- Episodes show the series poster in libraries and rows by default. Episode thumbnails appear in a season's episode list. Existing installs keep their setting: Settings › Appearance › Episode poster.

### Installer
- The installer always shows the install folder page, so the install location can be chosen.
