## Plezy Retrowave 0.8.1

### Android TV (e.g. NVIDIA Shield)
- The Android app is now called **Plezy Retrowave**, with a retrowave launcher icon and TV home-screen banner.
- It installs as its own app (`com.thetwistedchi.plezyretrowave`), so it sits next to the official Plezy instead of replacing it. Coming from an earlier Android build of this fork, sign in once again.
- The quality and language pills under posters now also show on Android TV, and their switch is in Settings › Appearance there too.
- Hide watched per Home row works on TV: long-press (Select held) a title in a Home row and pick **Hide watched in this row** or **Show watched in this row**. A row emptied this way stays visible so it can be shown again.
- The Home spotlight on TV shows the rating median (★) next to the other scores.
- The trailer button searches YouTube and opens the trailer in the device's YouTube app. The server's own trailer is the fallback.
- **Remember tracks per title** is listed in the playback settings on every platform.
- Library filters (quick chips, active pills, saved sets, Surprise me), Play from start, Similar in your library and Startup library already work on Android TV.

### All platforms
- New installs start with the Retrowave theme on every platform (Android TV used to start with OLED). An already chosen theme is kept.
- Manage Libraries marks the focused library clearly: it is tinted and outlined in the accent colour, more strongly while the row itself has focus.
- Smoother browsing: the background lookups for poster pills and rating medians use a lighter server request that skips chapters and markers, and run one at a time on TV devices. The page background is no longer repainted while scrolling. Quick filters and **Similar in your library** remember what they looked up per library, so reopening a library or another details page needs fewer requests.
- Hide watched per Home row is also in the right-click menu of a title in that row.
- The hover preview no longer blocks scrolling with the mouse wheel.
