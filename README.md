<img src="Resources/icon.png" width="128" alt="Suflir icon">

# Suflir

A free teleprompter for the MacBook notch, with no word limit. The script sits
right under the camera, so reading it looks like eye contact.

- Scrolls with your voice (and waits when you stop), or at a steady speed
- Script library with Trash
- Can stay hidden from screen sharing and recording
- Lives in the menu bar, with system-wide shortcuts

## Install

Pick either way. Both install the same app.

**1. Download**

1. Download [Suflir.dmg](https://github.com/anasark/suflir/releases/latest/download/Suflir.dmg).
2. Open it and drag Suflir into Applications.
3. Open Suflir. macOS blocks it the first time, because the app is not signed
   with a paid Apple developer account. Go to System Settings › Privacy &
   Security and click "Open Anyway". You only do this once.

**2. Terminal**

Paste this line and press Return. There is no macOS warning this way.

```bash
curl -fsSL https://suflir.anasabdur.com/get.sh | bash
```

Needs a Mac with Apple silicon (M1 or newer) and macOS 14 or later. More at
[suflir.anasabdur.com](https://suflir.anasabdur.com).

## Build from source

Needs the Xcode command line tools.

```bash
./install.sh
```

This builds the app, puts it in `/Applications` and opens it. Run it again
after any code change. It also writes `build/Suflir.dmg` and
`build/Suflir.zip`, the files to upload when publishing a release.

## Publishing a release

1. Run `./install.sh`.
2. On GitHub, create a new release and attach both `build/Suflir.dmg` and
   `build/Suflir.zip`. Keep those file names: the website downloads
   `Suflir.dmg` and `get.sh` downloads `Suflir.zip` from the latest release.

The website is the `docs/` folder, served by GitHub Pages.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥Space | Start or pause |
| ⌃⌥P | Show or hide the prompter |
| ⌃⌥↑ / ⌃⌥↓ | Scroll back or forward |
| ⌃⌥R | Restart from the top |
| ⌃⌥E | Open the editor |

## Contributing

Anyone is welcome to help develop Suflir. Changes come in as pull requests
and are merged only after the maintainer reviews and approves them. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Suflir is free and open source under the [MIT License](LICENSE). Anyone may
use, change and share it, as long as the copyright notice stays in place.

Copyright © 2026 Anas · [anasabdur.com](https://anasabdur.com)
