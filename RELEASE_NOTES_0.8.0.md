## Plezy Retrowave 0.8.0

Everything new since 0.7.1.

### Library filters
- **Quick filters** next to Filters and Sort toggle common filters with one click: **Unwatched**, **4K**, **HDR**, **Audio** in the app's language (e.g. `Audio: EN`) and **Added recently** (last 30 days). Each chip only appears when the library's server offers that filter, and it sets the same filter the Filters panel shows.
- **Active filters as pills**: a second row under the bar lists every active filter (e.g. `Genre: Action`). Clicking a pill removes that filter.
- **Saved filter sets**: the **Saved** chip stores the current filters and sort under a name, per library. Picking a set applies it again; sets can be deleted from the same menu.
- **Surprise me** opens a random title from the current filtered list.
- The chip bar scrolls sideways when it no longer fits, and follows the D-pad.

### Libraries
- Switching back to a library returns to the scroll position it was left at.
- Settings › General › **Startup library** picks the library the Libraries section opens on after starting the app. "Last used" keeps the previous behaviour.

### Home
- Each Home row has an eye toggle next to its title (shown on hover, or always while active) that hides titles already watched in that row. It follows the same watched state as the poster check mark, including titles marked watched in the app. The choice is kept per row.

### Posters
- Resting the mouse on a poster shows a preview with the year, runtime, genres, the rating median and the plot when the list includes one (seasons and some episodes have none). It uses only what the list already loaded, so it makes no extra requests.
- Settings › Appearance has a switch for the preview and a **Hover preview delay** from 0.25 s to 2.5 s (default 0.65 s).

### Details page
- When a title can be resumed, a **Play from start** segment (↻) sits next to Resume.
- The trailer button searches YouTube for the trailer and plays it in the YouTube player, so it works with the mini player and the queue. When nothing is found, the server's own trailer plays. Without the in-app YouTube player, the server's trailer is used as before.
- A new row **Similar in your library** lists up to 20 titles from the same library that share genres with the title, ranked by how many genres they share and then by their score.

### Player
- The audio track, subtitle track and zoom mode picked for a movie or series are remembered for that title. A series shares one choice across its episodes, matched by language, so another episode's file picks the same language. Can be turned off under Settings › Playback › **Remember tracks per title**.

### YouTube
- **Channel groups** on the subscriptions page: **New group** creates a named set of channels (e.g. Music, Tech). Selecting a group shows only videos from its channels. Right-click or long-press a group to rename, change or delete it.
- **Suggest groups** proposes one group per YouTube category (Music, Gaming, Science & Technology and so on), based on each channel's most common video category, and creates the ones picked. A suggestion with the name of an existing group adds its channels to that group. The category comes with the video details the app already loads for a signed-in account, so it costs no extra requests. Channels followed without a Google account have no category and are picked by hand.
- When editing a group, channels are sorted by category and show it, and a category chip ticks all its channels at once.
- YouTube can be chosen as the startup section under Settings › General.

### General
- Pressing **?** anywhere outside a text field shows all keyboard shortcuts, including the player keys as currently set.
- The README now states that this fork is built with AI assistance for personal use, with no support or guarantees.
