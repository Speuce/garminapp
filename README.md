# JumpStart

A Connect IQ alarm app for Instinct 2, fenix 7 Pro and Forerunner 255 Music.
Complete five detected jumping jacks to stop the alarm.

## On the watch

- **Set an alarm:** select **Add alarm** with UP/DOWN, press START/GPS, then set the time and repeat rule. Confirm to save.
- **Edit or test:** hold UP/MENU for alarm options, **Test now** or **Test in 5 min**. Test options are also available on **Add alarm**.
- **Go to sleep:** enable an alarm, press UP from the first alarm to select the moon, then START/GPS. Sleep mode dims the screen and shows the next alarm and live heart rate.
- **Stop the alarm:** stand still briefly, then do jumping jacks. The first three qualifying reps are credited together. The animated figure is a pacing guide; it moves independently of the counter.

Keep JumpStart open in sleep mode for automatic ringing. If the app is closed,
Garmin shows **Tap to open** instead; background timing can also be delayed.
BACK leaves sleep mode or cancels a test, but does not dismiss a real alarm.
The app cannot block Garmin's system controls or shutdown shortcuts.

## Build and sideload

Requires Java, a selected Connect IQ SDK, the target device package and a signing
key. Place the key at `developer_key` or pass `-Key <path>`.

```powershell
.\build.ps1 -Device instinct2 -Release  # Build for the watch
.\build.ps1 -Device instinct2 -Run      # Open in the simulator
.\build.ps1 -Device instinct2 -Test     # Run native tests
```

Use `fenix7pro` or `fr255m` for the other devices. Output is in `bin/<device>/`;
test results are in `test-results.txt` in that directory.

Copy `bin/<device>/JumpStart.prg` to the watch's `GARMIN/APPS/`, safely eject it,
and open JumpStart. Set an alarm in the app or use its test options.

On macOS, `make build`, `make test` and `make install` are available; configure
`SDK_DIR`, `DEVICE`, `KEY` and `WATCH` as needed.

## Motion detection

The Monkey C detector combines adaptive X/Y/Z timing with PCA and impact checks.
It is experimental: arm movements can still count, and real jacks can be missed.
Python is used only for local analysis.

Recorded samples are in `recordings/`; native tests are in `test/`.
Earlier experiments are documented in the [PCA report](docs/pca/report.html).
For device diagnostics, create `GARMIN/APPS/LOGS/JumpStart.TXT` before testing.
The app logs motion and vibration events for up to 60 seconds per alarm; collect
that file and its `.BAK` afterward.
