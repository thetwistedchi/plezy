## Plezy Retrowave 0.9.3

### Updates
- The update check runs on every start (it used to wait up to 20 hours between checks) and again every 6 hours while the app stays open, so a new release shows its update dialog soon after it is published. **Later** asks again at the next check; **Skip this version** still hides that release for good. Both follow the **Check for updates on startup** setting.
- The update dialog shows the release notes formatted (headings, lists, bold) instead of raw text.
- After an update, the first start shows once what is new in the installed version.
- The upstream Plezy updater is switched off completely, so it can never offer upstream releases in place of this fork.

### Libraries
- The library search is now also on phones, at the end of the tab strip.
