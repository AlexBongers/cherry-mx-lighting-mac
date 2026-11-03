# Cherry MX 10.0N RGB lighting protocol (USB 046A:00E2)

Worked out by watching Cherry Utility 3.12 (Windows) talk to the keyboard. Nothing here comes from Cherry documentation, so treat it as observed behaviour.

Cherry Utility uses `WriteFile` with 64 bytes to the HID interface `MI_01` and reads 64 bytes back after each write. On macOS this is the `IOHIDDevice` that reports `MaxOutputReportSize = 64`, and the reports are sent as output reports with report ID `4`.

## One lighting change = five reports (rest of each 64 bytes is zero)

| # | Bytes | Note |
|---|---|---|
| 1 | `04 00 00 01 00 00 00 55` | constant |
| 2 | `04 00 00 06 08 01 00 55 MM BB SS 01 00 RR GG BB` | settings |
| 3 | `04 00 00 02 00 00 00 55` | constant |
| 4 | `04 00 00 05 01 15 00 55` | constant |
| 5 | `04 00 00 05 08 01 00 55` | constant |

## Report 2, indexed from 0

| Byte | Meaning |
|---|---|
| 8 | `MM` effect |
| 9 | `BB` brightness, 0 (off) to 4 |
| 10 | `SS` speed, 0 (fast) to 4 (slow) |
| 11 | `01`, unknown (probably direction) |
| 13 to 15 | `RR GG BB` colour |

Brightness `0` switches all lighting off, `1` was visibly dimmer than `4`, and `ff 00 00` with Static gave solid red. These were confirmed on the keyboard.

## Effects

| Effect | MM | Effect | MM |
|---|---|---|---|
| Wave | 00 | Rolling | 0a |
| Spectrum | 01 | Curve | 0c |
| Breathing | 02 | Scan | 0f |
| Static | 03 | Radiation | 12 |
| Custom | 08 | Ripples | 13 |
| | | Single Key | 15 |

## Open questions

- Byte 11, probably direction. Not captured.
- Whether the four constant reports are required, or report 2 alone is enough.
- Custom (`08`) and per-key colours.
- Other Cherry models. A capture of Cherry Utility changing the effect on another model, plus its USB ID, would help a lot.

## How it was captured

API Monitor (32-bit, attach method Remote Thread) on Cherry Utility inside a Windows 11 ARM VM with the keyboard passed through, filtered on the `CreateFile`, `WriteFile` and HID APIs. USBPcap does not load on Windows for ARM, so a USB capture was not possible there.
