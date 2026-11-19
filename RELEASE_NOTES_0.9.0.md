## Plezy Retrowave 0.9.0

Everything new since 0.8.0. This release adds an Android and Android TV build (tested on an NVIDIA Shield).

### Android and Android TV
- The Android app is called **Plezy Retrowave**, with a retrowave launcher icon and TV home-screen banner.
- It installs as its own app (`com.thetwistedchi.plezyretrowave`), next to the official Plezy instead of replacing it.
- Rating medians, the quality and language pills, library filters (quick chips, active pills, saved sets, Surprise me), Play from start, Similar in your library, Startup library and per-title track memory all work on Android.
- On TV, the details page shows every fetched score (Letterboxd, Trakt, MDBList, OMDb, MyAnimeList) in its header, and a ★ button in the action row opens the comparison of all scores with their median.
- On TV, the quality and language pills also show in the Home rows.
- On TV, the Home spotlight shows the rating median (★) next to the other scores.
- Hide watched per Home row works on TV: long-press (Select held) a title in a Home row and pick **Hide watched in this row** or **Show watched in this row**. A row emptied this way stays visible so it can be shown again.
- The trailer button searches YouTube and opens the trailer in the device's YouTube app. The server's own trailer is the fallback.
- The API key dialogs (Settings › Services › Rating sources) explain where the key is kept and, on TV, that the Google TV app on a phone can type or paste it into the field.
- YouTube subscriptions and the in-app YouTube player stay Windows-only: Android has no YouTube tab, no YouTube entry in Settings › Services and no YouTube startup option.

### Library and Home
- The **Audio** quick filter opens a list of every audio language in the library (the app's language first, plus "Any language") and shows the chosen one on the chip, e.g. `Audio: German`. Like all filters, the choice is kept per library until changed.
- Hide watched per Home row is also in the right-click menu of a title in that row.
- Manage Libraries marks the focused library clearly: it is tinted and outlined in the accent colour, more strongly while the row itself has focus.

### Posters
- The quality and language pills work in every theme, drawn in the theme's own colours (Retrowave keeps its neon look).
- On narrow posters (TV, dense grids) the pill row no longer cuts off the language pill: quality and HDR merge into one pill (`4K HDR`) and the languages shorten to the first one plus a count (`DE +2`) as far as needed to fit.
- The watched check mark is 25 % smaller.
- The hover preview no longer blocks scrolling with the mouse wheel.

### Details page and player
- Clicking the **Median** card lists every score side by side: each site's own value, the same score on 0–100 as a bar, a line marking the median, the range of the scores and which ones count (the Tomatometer does not).
- Desktop player: the title in the top bar links to details pages. For an episode, the series name opens the series (on that episode's season) and the `S1 · E3 · Title` line opens the episode; for a movie, the title opens the movie. The player moves into the mini player bar and keeps playing.

### General
- New installs start with the Retrowave theme on every platform. An already chosen theme is kept.
- Smoother browsing: the background lookups for poster pills and rating medians use a lighter server request that skips chapters and markers, and run one at a time on TV devices. The page background is no longer repainted while scrolling. Quick filters and **Similar in your library** remember what they looked up per library, so reopening a library or another details page needs fewer requests.
- **Remember tracks per title** is listed in the playback settings on every platform.
