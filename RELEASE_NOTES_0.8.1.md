## Plezy Retrowave 0.8.1

### Android TV (e.g. NVIDIA Shield)
- The details page shows every fetched score (Letterboxd, Trakt, MDBList, OMDb, MyAnimeList) in its header, and a ★ button in the action row opens the comparison of all scores with their median.
- The API key dialogs (Settings › Services › Rating sources) explain where the key is kept and that the Google TV app on a phone can type or paste it into the field.
- The Android app is now called **Plezy Retrowave**, with a retrowave launcher icon and TV home-screen banner.
- It installs as its own app (`com.thetwistedchi.plezyretrowave`), so it sits next to the official Plezy instead of replacing it. Coming from an earlier Android build of this fork, sign in once again.
- The quality and language pills under posters now also show on Android TV, including the Home rows, and their switch is in Settings › Appearance there too.
- Hide watched per Home row works on TV: long-press (Select held) a title in a Home row and pick **Hide watched in this row** or **Show watched in this row**. A row emptied this way stays visible so it can be shown again.
- The Home spotlight on TV shows the rating median (★) next to the other scores.
- The trailer button searches YouTube and opens the trailer in the device's YouTube app. The server's own trailer is the fallback.
- **Remember tracks per title** is listed in the playback settings on every platform.
- Library filters (quick chips, active pills, saved sets, Surprise me), Play from start, Similar in your library and Startup library already work on Android TV.

### All platforms
- The **Audio** quick filter now opens a list of every audio language in the library (the app's language first, plus "Any language") and shows the chosen one on the chip, e.g. `Audio: German`.
- The watched check mark on posters is 25 % smaller.
- Desktop player: the title in the top bar links to details pages. For an episode, the series name opens the series (on that episode's season) and the `S1 · E3 · Title` line opens the episode; for a movie, the title opens the movie. The player moves into the mini player bar and keeps playing.
- Clicking the **Median** card on a details page lists every score side by side: each site's own value, the same score on 0–100 as a bar, a line marking the median, the range of the scores and which ones count (the Tomatometer does not).
- On narrow posters (TV, dense grids) the pill row no longer cuts off the language pill: quality and HDR merge into one pill (`4K HDR`) and the languages shorten to the first one plus a count (`DE +2`) as far as needed to fit.
- The quality and language pills under posters now work in every theme, drawn in the theme's own colours (Retrowave keeps its neon look).
- YouTube appears only where its in-app player exists (Windows): on Android and Android TV there is no YouTube tab, no YouTube entry in Settings › Services and no YouTube startup option. Trailers still open in the device's YouTube app.
- New installs start with the Retrowave theme on every platform (Android TV used to start with OLED). An already chosen theme is kept.
- Manage Libraries marks the focused library clearly: it is tinted and outlined in the accent colour, more strongly while the row itself has focus.
- Smoother browsing: the background lookups for poster pills and rating medians use a lighter server request that skips chapters and markers, and run one at a time on TV devices. The page background is no longer repainted while scrolling. Quick filters and **Similar in your library** remember what they looked up per library, so reopening a library or another details page needs fewer requests.
- Hide watched per Home row is also in the right-click menu of a title in that row.
- The hover preview no longer blocks scrolling with the mouse wheel.
