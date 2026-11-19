## Plezy Retrowave 0.9.2

### Updates
- The app now checks this fork's own GitHub releases for updates (at most once a day on startup, and with **Check for updates** in Settings, which also shows the installed version). It no longer looks at upstream Plezy releases.
- The update dialog shows the release notes and offers, depending on the installation:
  - **Windows (installed):** **Update and restart** downloads the new installer, installs it quietly and reopens the app. Settings and sign-ins are kept.
  - **Windows (portable):** **Open download page**, since a portable folder is replaced by hand.
  - **Android and Android TV:** **Download and install** downloads the matching APK and opens Android's install prompt. The first time, Android asks to allow installing apps from Plezy Retrowave.
- **Skip this version** hides that release until a newer one comes out; **Later** asks again next time.
- Automatic checks follow the existing **Check for updates on startup** setting.
- From this version on, Android updates only install over an existing copy if both were built with the same signing key.
