## Plezy Retrowave 0.9.1

### Android and Android TV
- Lighter on weak devices (TV sticks such as Fire TV or Chromecast with Google TV): when the app runs in its reduced visual-effects tier, which it chooses on its own for 32-bit or low-memory devices, the fork's extras hold back as well:
  - no background lookups for the language pills and rating medians (the pills still show quality and HDR, and medians appear once a title's details page was opened),
  - a flat page colour instead of the Retrowave gradient,
  - fewer titles fetched for **Similar in your library**.
- The tier can also be chosen by hand under Settings › Appearance › Visual effects.

### Rating sources
- Saving an MDBList or OMDb key now shows the site's own reason when the test fails, e.g. `key rejected (Invalid API key!)`.
- OMDb's daily request limit no longer marks a working key as rejected; the key shows as saved and OMDb is asked again later.
