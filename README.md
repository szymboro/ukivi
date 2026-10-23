<p align="center">
  <img src="Support/AppIcon.png" width="128" alt="uKivi icon: a red kiwi bird">
</p>

<h1 align="center">uKivi</h1>

<p align="center">
  A fast, private ad blocker for Safari on iPhone and iPad.<br>
  uBlock Origin's filter lists, converted for Safari, updated on your phone.<br>
  Built entirely on Linux, no Mac needed.
</p>

---

## Features

- **Blocks ads, trackers, cookie banners and pop-ups** in Safari, using EasyList, EasyPrivacy, uBlock Origin's lists, Fanboy's Annoyance List and Polish lists (about 150,000 rules).
- **Private by design.** Safari applies the rules itself, so uKivi never sees what you browse.
- **Updates on the phone.** Filter lists are downloaded and converted on the device every day in the background. If Safari rejects an update, the previous rules are restored.
- **Your own lists and filters.** Add any uBlock Origin or AdBlock Plus list by URL, or write your own rules (`||ads.example.com^`, `example.com##.banner`, `@@||example.com^`).
- **On/off switch** for all blocking, and **allowed sites** where nothing is blocked.
- **uKivi Extras**, an optional Safari extension: tap any element on a page to hide it, and pause blocking per site from the toolbar.

## Install

### From a release (SideStore / AltStore)

1. Download `uKivi-<version>.ipa` from [Releases](../../releases).
2. Open it with **SideStore** or **AltStore** and **keep the app extensions** when asked.
   uKivi needs 4 App IDs (the app plus 3 extensions). Free Apple accounts can create 10 per week and have at most 3 sideloaded apps installed at once.
3. Set it up on the iPhone (below).

> **LiveContainer won't work.** The blockers are Safari extensions, and those only run when the app is installed normally.

### Set up on the iPhone

1. Open **Settings → Apps → Safari → Extensions**.
2. Turn on **uKivi Ads** and **uKivi Privacy**.
3. Optional: turn on **uKivi Extras** and set it to **Allow** on every website.
4. Open uKivi. The status should say **Protection on**.

## Build from source (Linux)

uKivi is built with [xtool](https://github.com/xtool-org/xtool), a cross-platform replacement for Xcode. These steps are for Fedora; other distributions are similar.

### One-time setup

1. **Swift 6.4** via [swiftly](https://swift.org/install/linux). Fedora's own `swift-lang` package is too old.
2. **Xcode 27.1** `.xip` from [developer.apple.com/download](https://developer.apple.com/download/all/?q=Xcode). xtool extracts the iOS SDK from it.
3. **xtool**, from its latest release:
   ```bash
   curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o xtool
   chmod +x xtool && sudo mv xtool /usr/local/bin/
   xtool setup
   ```
   Log in with an **API key** (paid developer account) or a **password** (free account).
4. **iPhone:** turn on **Settings → Privacy & Security → Developer Mode**, connect it by USB and tap **Trust**.
5. **Your own bundle ID:** change `com.szymonb.ukivi` in `xtool.yml` and `group.com.szymonb.ukivi` in `Support/uKivi.entitlements`. The group must be `group.` + the bundle ID.

### Free Apple accounts need a patched xtool

The app and its extensions share settings and downloaded rules through an **App Group**. Stock xtool leaves App Groups out when signing with a free account (a `FIXME` in its source), and then uKivi shows *"Shared storage isn't available"*. [`Tools/xtool-free-app-groups.patch`](Tools/xtool-free-app-groups.patch) fixes this:

```bash
sudo dnf install libimobiledevice-devel libplist-devel libusbmuxd-devel libimobiledevice-glue-devel
git clone https://github.com/xtool-org/xtool ~/Development/xtool-patched
cd ~/Development/xtool-patched
git apply ~/Development/ukivi/Tools/xtool-free-app-groups.patch
swift build -c release --product xtool
```

`run.sh` uses `~/Development/xtool-patched` automatically when it exists. Paid accounts can use stock xtool.

### Build and install

```bash
./run.sh            # build, sign and install on the connected iPhone
./run.sh --lists    # same, but download the latest filter lists first
```

To build an unsigned `.ipa` instead:

```bash
python3 Tools/convert_filters.py
xtool dev build --configuration release --ipa    # -> xtool/uKivi.ipa
```

## How it works

| Part | What it is |
|---|---|
| **uKivi Ads** | Safari content blocker: EasyList, uBlock filters, Polish lists, annoyance and cookie lists (~91k rules) |
| **uKivi Privacy** | Safari content blocker: EasyPrivacy, uBlock Privacy, plus your custom lists (~59k rules) |
| **uKivi Extras** | Safari web extension: element picker and per-site pause |
| **uKivi app** | Status, on/off switch, filter updates, allowed sites, custom lists |

Safari's rule format is much simpler than uBlock's, so some filters can't be converted. These are skipped: regex filters, scriptlets (`##+js`), procedural cosmetics (`:has-text`, `:upward`), `$redirect`, `$csp`, `$removeparam` and similar. That's about 5–15% of each list. Safari allows 150,000 rules per blocker; the app warns you if your custom lists go over.

The converter exists twice and both versions produce identical output:
- **`Tools/convert_filters.py`** (Python) builds the rules bundled with the app.
- **`Packages/FilterKit`** (Swift) runs on the phone for updates.

```bash
python3 Tools/test_convert_filters.py              # Python tests
(cd Packages/FilterKit && swift test)              # Swift tests (runs on Linux)
python3 Tools/compare_converters.py                # both on the real lists: must be identical
```

### Project layout

```
Package.swift                 app + 3 extensions (SwiftPM)
xtool.yml                     bundle ID, extensions, resources, entitlements
Sources/
  uKivi/                      SwiftUI app
  uKiviShared/                code shared by the app and extensions
  uKiviAds/, uKiviPrivacy/    content blocker entry points
  uKiviWebExtension/          native side of the Safari web extension
WebExtension/                 the Safari web extension (popup, element picker)
Packages/FilterKit/           filter converter in Swift (used on the phone)
Support/                      Info.plists, entitlements, icons (logo.svg is the source)
Tools/
  filters.json                which lists go into which blocker
  convert_filters.py          filter converter in Python (build time)
  compare_converters.py       checks both converters match
  make_icons.py               renders every icon from Support/logo.svg
  xtool-free-app-groups.patch xtool patch for free Apple accounts
Generated/                    converted rules bundled into the build
```

## Limitations

- **YouTube video ads aren't removed.** Doing it means changing YouTube's own scripts, which stopped videos from playing on iPhone.
- **Only Safari.** Ads inside apps (games, Instagram and so on) would need a DNS or VPN-based blocker.
- **No Control Center button.** That needs a widget extension, App Intents (which only build on macOS) and another App ID.
- **Free accounts:** apps stop opening after 7 days until you reinstall or refresh them, and you can have at most 3 sideloaded apps.

## Credits

- Filter lists: [EasyList](https://easylist.to), [uBlock Origin uAssets](https://github.com/uBlockOrigin/uAssets), [Fanboy](https://www.fanboy.co.nz), [Oficjalne Polskie Filtry](https://github.com/MajkiIT/polish-ads-filter), [EasyList Polish](https://easylist.to).
- Built with [xtool](https://github.com/xtool-org/xtool) by Kabir Oberai.

## License

[GPL-3.0](LICENSE). The bundled filter lists keep their own licenses (GPL-3.0 / CC BY-SA 3.0).
