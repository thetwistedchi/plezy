## Plezy Retrowave 0.6.1

### Mini player
- A **Mini player** button in the Plex player and the YouTube player shrinks the video into a bar along the bottom of the app, so you can keep browsing while it plays.
- The bar has the live video, title, back 10 s, play/pause, forward 30 s, next, volume, a button to open the full player again and a **Stop** button that ends playback and closes the player.
- **Back** (back arrow, Escape or the Back key) also minimizes the player instead of closing it. Turn it off under Settings › Playback › "Back opens the mini player".
- Clicking the small video or the title opens the full player again. Pages opened while it was minimized are closed when you do.
- Playing something else opens it in the full player; starting a YouTube video stops a minimized Plex video and the other way round.

### Picture
- The video always keeps its aspect ratio: the stretching fill mode is gone. The fit button switches between **Fit** and **Fit height**, which fills the screen's height and never cuts anything off at the top or bottom.
- Optional **Fill the screen when letterboxed** (Settings › Playback): detects black bars baked into a video and crops them, so wide films fill ultrawide screens. Works in both fit modes.

### HDR
- **HDR brightness boost** slider (Settings › Playback and the player's own settings, under the HDR switch; Windows): an extra lift for the midtones of HDR videos that look too dark. Off keeps the picture as mastered, HDR stays on at every setting, and changes apply right away.
- HDR videos use a brighter tone curve by default (`tone-mapping=bt.2446a`, `hdr-peak-percentile=99.5`, `hdr-contrast-recovery=0.3`). Lines in your own mpv config still win.

### Player
- Clicking the video plays or pauses it; double-click still toggles fullscreen. Turn it off under Settings › Playback.
- Play button down to 38 px in the Plex and YouTube players.
- Fixed: the page background covered the YouTube video.
