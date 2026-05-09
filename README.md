# Ole Miss Watch Face

A Garmin Connect IQ watch face for the Fenix 8 / Fenix 8 Pro 47 mm
(round AMOLED). Shows the current time, today's date, daily steps,
and a countdown to the next Ole Miss Rebels football kickoff over the
Ole Miss logo.

Schedule data is fetched in the background from ESPN's public API on
an adaptive cadence (daily off-season, every 15 min during games),
with a compiled-in static schedule as the offline / first-launch
fallback.

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
    ├── OleMissWatchFaceApp.mc    AppBase entry point + background wiring
    ├── OleMissWatchFaceView.mc   Layout + draw + low-power partial update
    ├── Schedule.mc               Schedule lookup (storage-first, static fallback)
    ├── ScheduleStore.mc          Application.Storage facade for fetched data
    ├── BackgroundService.mc      Adaptive-polling ESPN fetch
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

You should see the Ole Miss logo on a navy field, the current time and
date stacked on the right, daily steps in the upper-right strip, and a
countdown to the next game across the bottom. Until the first
successful background fetch lands ESPN data in storage, the schedule
falls back to the compiled-in 2025 array — which means out of season
you'll see the synthetic `Demo Opponent` two days out. Set
`INCLUDE_DEMO_GAME = false` in `Schedule.mc` to suppress it and show
the "Hotty Toddy" off-season filler instead.

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

## Live schedule data

`source/BackgroundService.mc` is a `Toybox.System.ServiceDelegate`
(annotated `(:background)`) that hits ESPN's free team-schedule
endpoint, parses events, and writes them to `Application.Storage` via
`ScheduleStore`. The watch face reads from storage on every redraw and
falls back to the compiled-in static schedule when storage is empty
(first launch, off-season, or fetch failures).

Polling is adaptive — the service re-registers itself for its own next
wake based on what's coming up:

| Situation                                  | Next wake          |
| ------------------------------------------ | ------------------ |
| No game in the next 24 h                   | + 24 h (daily)     |
| Next game inside the next 24 h             | at kickoff         |
| Inside live window (kickoff → kickoff +4½ h) | + 15 min         |

All wakes clamp to Connect IQ's 5-minute floor. Phone proximity is
required — Garmin routes background HTTP through Connect Mobile over
BLE, so missed wake-ups (phone out of range) are dropped rather than
caught up.

### Known gaps blocking real-hardware end-to-end

1. **ESPN response is too large.** The full team-schedule payload runs
   ~400 KB; Connect IQ's per-request JSON cap on watch faces is
   ~32 KB, so `makeWebRequest` will reject it as oversized. Standard
   workaround is a thin proxy (Cloudflare Worker / Vercel function /
   etc.) that hits ESPN, strips each event to
   `{opponent, kickoffSec, confirmed, status, home}`, and returns
   ~1 – 2 KB. Then point `BackgroundService.SCHEDULE_URL` at it.
2. **Out-of-season responses are empty.** ESPN's endpoint returns
   `events: []` until the new schedule is published (typically late
   spring / early summer). The static fallback in `Schedule.mc`
   covers this — refresh it each year when the new schedule drops.

## Next steps

- **Slim ESPN proxy.** See "Known gaps" above. This is the blocker for
  on-hardware live data; everything else hangs off it.
- **Refresh the static fallback for 2026.** Edit the array in
  `source/Schedule.mc → _buildStaticSchedule()`. Each row is
  `(opponent, isHome, year, month, day, hourUTC, minuteUTC, confirmed)`.
  Set `confirmed=false` for any TBD kickoff. The static schedule
  doubles as the off-season / offline fallback even after the network
  path is unblocked.
- **Live scores.** Add `:homeScore`, `:awayScore`, and `:gameClock`
  keys to the schedule entries (and to `ScheduleStore`'s persisted
  shape). In `_drawKickoffSection()`, when status is `STATUS_LIVE`,
  render a third line with the score / clock instead of the "LIVE"
  placeholder.
- **More Fenix 8 sizes.** Append product IDs (`fenix851mm`,
  `fenix843mm`, `fenix8solar51mm`, `fenix8solar47mm`) to the
  `<iq:products>` block in `manifest.xml`. The view sizes everything
  from `dc.getWidth()` / `dc.getHeight()`, so the layout already
  scales — but you may want device-specific resource directories
  (`resources-fenix851mm/...`) for per-size logo variants. The pattern
  is documented in `monkey.jungle`.
