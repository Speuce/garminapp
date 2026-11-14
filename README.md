# JumpStart

Trail-style alarm configuration for the Garmin fenix 7 Pro (`fenix7pro`) and Instinct 2 (`instinct2`), using Connect IQ API 3.4+.

The fenix uses the colour Trail layout. The Instinct uses a separate 176px monochrome layout, with context in its round subwindow. Both share the same button navigation and storage code.

**This version only saves alarm settings. It does not schedule notifications, wake the app, vibrate, play sounds, or create Garmin system alarms.** Enabled/disabled is a persisted setting for the future alarm implementation.

## On the watch

- UP / DOWN moves through lists; in number editors, UP increases and DOWN decreases.
- START selects a row or advances to the next field.
- Select **Add alarm**, set hour/minute/AM-PM, choose a repeat pattern, then press START at **Review alarm** to save.
- Presets: **Every day**, **Weekdays**, **Weekends**. **Custom week** supports chosen weekdays every 1-52 weeks, with a start date. **Every N days** supports 1-52 calendar-day intervals. **Once** stores a single date.
- Hold UP on a selected alarm for **Edit**, **Disable/Enable**, **Delete**, or **Add alarm**.
- Delete opens a confirmation with **Keep alarm** selected by default. Disable keeps the time and repeat settings; editing a disabled alarm leaves it disabled.
- BACK revisits the preceding field. Backing out of the first field offers **Keep editing** or **Discard**. Unsaved drafts never modify stored alarms.
- On custom weekdays, START toggles a day. Select **Done** or hold UP to continue. At least one day must remain selected.

The list starts empty. There are no automatically saved demo alarms. Up to 16 independent alarms can be stored. Dates are calendar dates and times are local wall-clock values. Weekly-cycle data uses Monday-Sunday weeks and the chosen start date; no occurrence calculation runs in the watch app yet.

## Storage

`AlarmStore` writes a versioned snapshot to `Application.Storage` under `jumpstart.alarms.v1`, immediately on Save, Disable/Enable, or confirmed Delete. It reads the value back before reporting success. This is Garmin's persistent device filesystem API, not browser storage or an in-memory settings mock. It requires no manifest storage permission.

The snapshot contains `version`, `nextId`, and an `alarms` array. Each record stores a stable ID, 24-hour hour/minute, enabled flag, repeat type, weekday bitmask (Monday is bit 0), interval, and start year/month/day. Only serializable values are stored. Failed or unconfirmed writes retain the draft and report an error; unreadable or unknown-schema data is left untouched.

See [Garmin: Persisting Data](https://developer.garmin.com/connect-iq/core-topics/persisting-data/) for the on-disk behavior of `Storage.setValue`.

## Build and test

Requires Java, a selected Connect IQ SDK with the appropriate device package, and the local signing key `developer_key` (excluded from Git).

```powershell
.\build.ps1          # bin/fenix7pro/JumpStart.prg
.\build.ps1 -Run     # Build and launch on the simulator
.\build.ps1 -Release # Release binary: bin/fenix7pro/JumpStart.prg
.\build.ps1 -Test    # Seven simulator tests; separate scratch storage keys
.\build.ps1 -Device instinct2 -Run
.\build.ps1 -Device instinct2 -Release # bin/instinct2/JumpStart.prg
```

In VS Code, choose **Run JumpStart (fenix 7 Pro)** or **Run JumpStart (Instinct 2)**, then press F5. If the simulator was started hidden for command-line tests, open the SDK's CIQ Simulator to interact with it. Simulator keyboard controls: arrow keys, Enter, Escape, and uppercase **M** for the watch's hold-UP menu.

To check persistence across simulator restarts:

```powershell
.\build.ps1 -Test -TestName persistenceStage1Write
# Close and reopen the CIQ Simulator, then:
.\build.ps1 -Test -TestName persistenceStage2Read
```

The second stage reads the record left by the first launch, verifies its time and disabled state, and removes its scratch key. These probes never replace the normal alarm list. The functional suite covers add/edit, cancellation, disable/enable, delete confirmation, custom rules, leap dates, limits, failed writes, and a real storage round trip.

Both targets pass the functional suite and the persistence check across a simulator restart. Add `-Device instinct2` to the test commands above to check that target. Each device requires its own binary from `bin/<device>/JumpStart.prg`; copy only the matching build to its `GARMIN/APPS` folder. The build script does not install to a physical watch.

## Code

- `source/common/JumpStartApp.mc`: app initialization and dependency wiring.
- `source/common/AlarmData.mc`: record creation, validation, and formatting; no scheduler.
- `source/common/AlarmStore.mc`: persistent storage, versioning, and write verification.
- `source/common/AlarmController.mc`: draft editing and button navigation state machine.
- `source/fenix7pro/TrailView.mc`, `source/instinct2/TrailView.mc`: device-specific rendering and contextual hints.
- `source/common/TrailDelegate.mc`: Garmin button behaviors.
- `source/common/AlarmTests.mc`, `source/common/AlarmLimitTests.mc`: simulator tests, excluded from normal builds.

## Design gallery

Open [design/jumpstart.html](design/jumpstart.html) directly in a browser. It retains the Trail, Orbit, and Roster design comparisons. **Trail is the implemented direction.** Gallery examples use 7:00 AM weekdays and 8:30 AM weekends; its browser-local settings are independent of the watch app.
