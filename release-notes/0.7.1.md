## Plezy Retrowave 0.7.1

### Posters
- The rating median now appears on far more posters. Library lists carry at most two scores per title, often only the Tomatometer, which the median leaves out. Posters therefore use the full median once a title's details page was opened, and otherwise fetch the title's scores from its own Plex server in the background, a few at a time. With an MDBList key, MDBList fills in when the server has too few scores. Medians are kept on disk, so each title is looked up only once every two weeks.
- Seasons and episodes in Home rows (such as Recently added) show their series' median.
- New look for poster badges: the rating (★), the unwatched-episode count and the watched check mark are small dark purple pills with a muted neon rim and tinted text, centred exactly.
- Under each poster a row of pills shows the resolution, HDR and the audio languages (e.g. `4K` `HDR` `DE · EN`; more than two languages as `+2`). Languages come from the title's own Plex server, looked up once per title and kept for a month; series use their first episode. Can be turned off under Settings › Appearance.
- Row headings with their icons and arrows, and card titles, use a periwinkle blue that no other text uses.

### YouTube
- A **Continue where you left off** card at the top of the subscriptions page resumes the last unfinished video with one click, at the position it stopped. Dismissing it hides that video.
- The same video appears as the first card of Home's **Continue watching** row, in poster size with a YouTube mark and its progress. Right-click hides it.
- The **⋮** menu of a video has **Copy link**, and **Copy link at …** for a video watched part way, which starts at the saved position.
- In the player's **More from this channel** panel, each video has a button that adds it to the queue and the watchlist; queued videos show a check.

### Other themes
- The Windows title bar, the mini player bar, the YouTube pages and player panels, and the rating badge on posters follow the active theme. The retrowave colours stay in the Retrowave theme.
