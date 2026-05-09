# Ole Miss Watch Face

A Garmin Connect IQ watch face for the Fenix 8 (47 mm AMOLED, 416 × 416).
Shows the current time, today's date, and a live countdown to the next
Ole Miss Rebels football kickoff over an Ole Miss logo background.

## What's in the box

```
om-watch-face/
├── manifest.xml                  Connect IQ app manifest (targets: fenix847mm, fenix8pro47mm)
├── monkey.jungle                 Build configuration
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml         Bitmap registry
│   │   ├── launcher_icon.png     Placeholder — replace with your icon
│   │   └── olemiss_logo.png      Placeholder — REPLACE with the real logo
│   ├── properties/properties.xml Default values for user settings
│   ├── settings/settings.xml     UI for user settings (24h toggle)
│   └── strings/strings.xml       App name + setting labels
└── source/
    ├── OleMissWatchFaceApp.mc    AppBase entry point
    ├── OleMissWatchFaceView.mc   Layout + draw + low-power partial update
    ├── Schedule.mc               Static 2025 schedule + next-game lookup
    └── CountdownFormatter.mc     "2d 14h 32m" / "14h 32m" formatter
```

## Prerequisites

1. **Connect IQ SDK 5.0.0 or newer** — install via the [Connect IQ SDK
   Manager](https://developer.garmin.com/connect-iq/sdk/) and download the
   Fenix 8 device profile.
2. **VS Code** with the [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c).
3. A **developer key** — generate one in VS Code via the command palette:
   `Monkey C: Generate a Developer Key`.

## Build & run in the simulator

From the project root:

```bash
# 1. Open the folder in VS Code
code .

# 2. In VS Code: Cmd/Ctrl-Shift-P → "Monkey C: Build for Device"
#    Pick "fenix847mm".  This produces bin/OleMissWatchFace.prg.

# 3. Run it: Cmd/Ctrl-Shift-P → "Monkey C: Run No Debug"
#    The Connect IQ simulator launches with the watch face loaded.
```

You should see a navy square (the placeholder logo), the current time at
the top, today's date below, and a `~2d Xh Ym` countdown to a synthetic
"Demo Opponent" game in the lower third. The demo game is created at
runtime as `Time.now() + 2 days`, so it will always be ~48 hours out.

CLI alternative (skip VS Code):

```bash
monkeyc \
  -d fenix847mm \
  -f monkey.jungle \
  -o bin/OleMissWatchFace.prg \
  -y ~/garmin/keys/developer_key.der \
  -w

connectiq                                # start the simulator
monkeydo bin/OleMissWatchFace.prg fenix847mm
```

Your developer key lives at `~/garmin/keys/developer_key.der`
— the `-y` flag above already points at it. If you ever regenerate the
key, update the path in this README and in any wrapper scripts you add
under `scripts/`.

## Sideload onto a physical Fenix 8

The **Fenix 8 Pro 47mm** uses MTP for USB transfer — there is no Mass
Storage mode, so the watch never gets a drive letter and you cannot
`cp` to it from WSL. Use Windows Explorer for the final drag.

1. **Build a release `.prg`** targeting your watch's product ID. For
   the Fenix 8 Pro 47mm:

   ```bash
   SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b
   "$SDK/bin/monkeyc" \
     -d fenix8pro47mm \
     -f monkey.jungle \
     -o bin/OleMissWatchFace.prg \
     -y ~/garmin/keys/developer_key.der \
     -w -r
   ```

   For the regular Fenix 8 47mm, swap `-d fenix8pro47mm` for
   `-d fenix847mm`. The `-r` flag produces a release (non-debug) build.

2. **Stage the `.prg` somewhere Windows can see it.** WSL paths exposed
   via `\\wsl.localhost\...` work in Explorer but Shell COM/MTP copies
   choke on them, so the simplest move is a copy under `/mnt/c/`:

   ```bash
   cp bin/OleMissWatchFace.prg /mnt/c/Users/<you>/AppData/Local/Temp/
   ```

3. **Plug the watch in.** On the watch, USB mode must be MTP
   (*Settings → System → USB Mode*). The watch will appear in Windows
   Explorer under "This PC" as `fenix 8 Pro - 47mm`.

4. **Drag the `.prg` into the watch's Apps folder** via Explorer:

   ```
   This PC → fenix 8 Pro - 47mm → Internal Storage → GARMIN → Apps
   ```

   Note `Apps` is mixed case, not `APPS`. Wait for the progress bar to
   finish (MTP is slow — ~30s for a 200 KB `.prg`).

5. **Disconnect.** Press **BACK** on the watch, or just unplug — MTP
   has no host-side write cache to flush, so it's safe to yank once
   Explorer's copy progress hit 100%.

6. **Activate the face:** *Settings → Watch Face → Connect IQ → Ole
   Miss Watch Face*.

## Settings

The user setting `Use24Hour` is exposed in Garmin Connect Mobile under the
watch face's settings panel. Default is 12-hour; flip to 24-hour and the
view re-renders on the next tick (we listen for `onSettingsChanged()` in
the App class).

## Next steps

These are wired up but not yet implemented — pick whichever you want to
tackle first:

- **Drop in the real logo.** Save the Ole Miss logo as a square PNG at
  `resources/drawables/olemiss_logo.png` (360 × 360 or larger looks best on
  the 416 × 416 face — anything bigger gets scaled down at draw time).
  Overwrite the placeholder file in place; `drawables.xml` already
  references it. While you're there, replace `launcher_icon.png` with a
  small (40 × 40-ish) version.
- **Update the schedule.** Edit the static array in
  `source/Schedule.mc → _buildStaticSchedule()`. Each row is
  `(opponent, isHome, year, month, day, hourUTC, minuteUTC, confirmed)`.
  Set `confirmed=false` for any TBD kickoff and the watch face will
  display "TBD" instead of a misleading countdown. To turn off the
  always-2-days-from-now demo entry once you're ready for production, set
  `INCLUDE_DEMO_GAME = false` near the top of the same file.
- **Switch to a backend feed.** `Schedule.getSchedule()` is the only
  function that knows how the array is built. Replace the call to
  `_buildStaticSchedule()` with a `Toybox.Communications.makeWebRequest`
  to your backend (returning the same `Array<Dictionary>` shape) and
  add `<iq:uses-permission id="Communications"/>` to the manifest. The
  view, the countdown formatter, and `getNextGame()` won't need any
  changes — the TODO marker in the file shows exactly where the network
  call slots in.
- **Live scores.** Add `:homeScore`, `:awayScore`, and `:gameClock` keys
  to the schedule entries. In `_drawKickoffSection()`, when status is
  `STATUS_LIVE`, render a third line with the score / clock instead of
  the "LIVE" placeholder.
- **More Fenix 8 sizes.** Append product IDs (`fenix851mm`, `fenix843mm`,
  `fenix8solar51mm`, `fenix8solar47mm`) to the `<iq:products>` block in
  `manifest.xml`. The view sizes everything from `dc.getWidth()` /
  `dc.getHeight()`, so the layout already scales — but you may want
  device-specific resource directories (`resources-fenix851mm/...`) for
  per-size logo variants. The pattern is documented in `monkey.jungle`.
