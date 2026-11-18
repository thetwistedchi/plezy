## Plezy Retrowave 0.7.0

### Rating median
- Movie and series posters show the median of their scores as a small star badge in the top left corner, on a 0–100 scale. It uses only the scores Plex already sends with the library, so scrolling makes no extra requests.
- The details page shows a **Median** card after Ratings & links, with the number of sources it is based on.
- Every score is converted to 0–100 first (IMDb 7.8/10 → 78, Letterboxd 3.9/5 → 78). The Tomatometer is left out: it is the share of positive reviews, not an average score.

### More rating sources
- New section **Settings › Services › Rating sources**:
  - **MDBList**: one request for IMDb, TMDB, Trakt, Letterboxd, Rotten Tomatoes, Metacritic and MyAnimeList. Needs a free API key from mdblist.com.
  - **OMDb**: IMDb, Tomatometer and Metascore when MDBList has none. Needs a free API key from omdbapi.com.
  - **MyAnimeList (Jikan)**: anime scores, no key needed.
- New cards in Ratings & links: **Metacritic**, **MyAnimeList** and the Rotten Tomatoes audience score.
- API keys are stored encrypted, are not part of settings exports, and are tested when saved. A key that a site rejects shows as "Key rejected".
- Without keys, or when a site does not answer, Letterboxd and Trakt scores are still fetched directly, now in parallel. A site that failed is asked again after 15 minutes instead of the next day.

### Letterbox detection
- Black bars are only cropped when they are about equally high at the top and bottom (or left and right), so dark scenes no longer cause wrong crops.
- A second check a few minutes into a film can only shrink the crop, correcting a too large first guess.
- The snapshots used for detection are taken at low quality, which avoids hitches on 4K HDR.

### Mini player
- Keyboard media keys control a minimized YouTube video.
- When a video ends while minimized and nothing plays next, the mini player closes on its own.

### Performance
- YouTube playback positions are kept in their own file and saved every 30 seconds and on pause, instead of rewriting the settings file every 5 seconds.
- The YouTube player is fully released after 10 minutes without use, freeing its memory. The next YouTube video then takes a second or two longer to start.
- Rating results are cached for about the last 300 titles.
