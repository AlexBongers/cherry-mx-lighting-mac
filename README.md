# cherry-mx-lighting-mac

A small native macOS menu bar app that controls the RGB lighting of a **Cherry MX 10.0N RGB** keyboard, and remaps keys. Cherry only ships its configuration tool for Windows; this fills the gap on the Mac.

> **Unofficial.** Not affiliated with or endorsed by Cherry. The lighting protocol was worked out by observing what Cherry Utility sends to the keyboard, for interoperability. Use at your own risk.

## Features

- **Lighting:** 10 effects (Wave, Spectrum, Breathing, Static, Rolling, Curve, Scan, Radiation, Ripples, Single Key), speed, brightness and a free RGB colour. One-click **Off**.
- **Key remapping** through `hidutil`: Caps Lock to Esc or Control, swap Option and Command for a PC layout, F7 to F12 as media keys, or your own pairs. It is reapplied when the keyboard is plugged in again.
- Lives in the menu bar, no Dock icon. About 40 MB of memory and 0% CPU when idle.

The interface is available in **English and Dutch** and has an **EN | NL** switch in the window (the first launch follows the language of macOS). Translations live in `cherry-remap/Resources/<lang>.lproj/Localizable.strings`; the English text is the key, so adding a language means adding one file.

## Tested on

- Cherry **MX 10.0N RGB**, USB `046A:00E2`, over USB
- macOS 27 on Apple Silicon

Other Cherry models may use the same protocol, but nothing else is tested. Feedback and captures from other keyboards are welcome, see [PROTOCOL.md](PROTOCOL.md).

## Build

You only need the Xcode Command Line Tools, not Xcode.

```bash
cd cherry-remap
./build.sh
open CherryRemap.app
```

`build.sh` compiles with `swiftc` and signs the app. SwiftUI's `@State` macro is not available in the Command Line Tools, so the code uses `ObservableObject` instead.

### Permissions

Writing to the keyboard needs **System Settings, Privacy & Security, Input Monitoring** for CherryRemap. macOS ties that permission to the app's code signature, so an ad-hoc signature loses it on every rebuild. To keep it, create a local code signing certificate named `CherryRemap Local Signing` in your login keychain and mark it as trusted for code signing; `build.sh` uses it automatically when it exists.

## Command line

The app can apply a setting once and quit, which is handy for testing and scripts:

```bash
open -n CherryRemap.app --args --apply <mode hex> <speed 0-4> [brightness 0-4] [RRGGBB]
# example: static red at full brightness
open -n CherryRemap.app --args --apply 03 2 4 ff0000
```

The result is written to `/private/tmp/cherry-lighting.log`.

## How it works

Every lighting change is five 64-byte HID output reports (report ID 4) to the keyboard's configuration interface. Only the second one carries the settings. Details and the byte layout are in [PROTOCOL.md](PROTOCOL.md).

## Not done yet

Effect direction, per-key colours and the Custom mode.

## License

[MIT](LICENSE)
