## Plezy Retrowave 0.8.0

### Home
- Each Home row has an eye toggle next to its title (shown on hover, or always while active) that hides titles already watched in that row. The choice is kept per row.

### Libraries
- Switching back to a library returns to the scroll position it was left at.
- Settings › General › **Startup library** picks the library the Libraries section opens on after starting the app. "Last used" keeps the previous behaviour.

### Posters
- Resting the mouse on a poster shows a preview with the plot, year, runtime, genres and the rating median. It uses only what the list already loaded. The delay before it appears and the preview itself can be set under Settings › Appearance.

### Details page
- When a title can be resumed, a **Play from start** segment (↻) sits next to Resume.
- The trailer button searches YouTube for the trailer and plays it in the YouTube player, so it works with the mini player and the queue. When nothing is found, the server's own trailer plays. Without the in-app YouTube player, the server's trailer is used as before.
- A new row **Similar in your library** lists up to 20 titles from the same library that share genres with the title, ranked by how many genres they share and then by their score.

### Player
- The audio track, subtitle track and zoom mode picked for a movie or series are remembered for that title. A series shares one choice across its episodes, matched by language, so another episode's file picks the same language. Can be turned off under Settings › Playback › **Remember tracks per title**.

### YouTube
- **Channel groups** on the subscriptions page: **New group** creates a named set of channels (e.g. Music, Tech). Selecting a group shows only videos from its channels. Right-click or long-press a group to rename, change or delete it.
- **Suggest groups** proposes one group per YouTube category (Music, Gaming, Science & Technology and so on), based on each channel's most common video category, and creates the ones picked. The category comes with the video details the app already loads for a signed-in account, so it costs no extra requests. When editing a group, channels are sorted by category, and a category chip ticks all its channels at once. Channels followed without a Google account have no category and are picked by hand.
- YouTube can be chosen as the startup section under Settings › General.

### General
- Pressing **?** anywhere outside a text field shows all keyboard shortcuts, including the player keys as currently set.
