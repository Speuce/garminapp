# JumpStart alarm

Connect IQ alarm app for Instinct 2 (`instinct2`) and fenix 7 Pro (`fenix7pro`).
This integration combines `main`'s alarm scheduling with the adaptive Monkey C
jumping-jack detector. Twenty confirmed jumping jacks dismiss a ringing alarm.

## Using the alarm

START opens the menu. Set time / Enabled controls the daily alarm. **Test ring**
starts a preview immediately (BACK cancels it without changing the daily alarm).
**Test in 5 min** arms a one-off alarm; completion restores the daily settings.
The actual alarm consumes START/BACK presses until the rep target is reached.
If sensor registration fails, the screen reports that and allows BACK to exit.

Keep the watch still briefly when ringing starts, then do jumping jacks. The
counter confirms three cycles before displaying the initial three reps. Sensor
sampling runs at 25 Hz only while the ring screen is visible and stops on exit.
There is no timer-generated rep count and no FIT activity is recorded by the alarm.

If the app is closed, Connect IQ's background service displays a prompt to open
it; accept that prompt to enter the jumping-jack screen. This is the Garmin
[background wake API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html#requestApplicationWake-instance_function),
not an unattended native system alarm. Foreground ringing is checked each second
on the home screen. Use the foreground flow for the first hardware test.

## Detector and validation

`source/RepCounter.mc` smooths all three axes, detects peak-relative returns, and
checks duration, X/Z range, vector magnitude and shape. Candidate timeouts and
spacing adapt to cadence. Three qualifying cycles confirm a run; further cycles
add one. Pauses reset pending confirmation. State has fixed size.

The original labelled recordings remain unchanged: 20/20 normal jacks and zero
counts for watch checks/marching. These cover one left-wrist Instinct 2 user,
not population-wide accuracy. The Monkey C tests include per-sample parity,
weak returns, cadence changes, calibration, pauses, recovery, exact alarm
completion, late callbacks, fresh sessions and one-off alarm scheduling.

`recordings/` contains the original FIT files and labels. `test/RecordedSamples.mc`
contains their XYZ samples in compiler-sized blocks and is excluded from normal
builds. The FIT accelerometer timestamps/offsets are invalid. For simulator FIT
playback, local copies in `build/alarm/` reconstruct timing at 25 Hz without
changing XYZ values. Python analysis and playback preparation stay local;
Python is not required to build or run the app.

## Build and test

Requires Java, a selected Connect IQ SDK, installed device packages and a signing
key (excluded from Git). Windows:

```powershell
.\build.ps1 -Device instinct2 -Run
.\build.ps1 -Device instinct2 -Test
.\build.ps1 -Device fenix7pro -Test
.\build.ps1 -Device instinct2 -Release
```

Use `-Key <path>` for a key outside this checkout. `-TestName <name>` selects a
unit test. Output is `bin/<device>/JumpStart.prg`; test summaries are saved in
`bin/<device>/test-results.txt`.

For a one-off sideload test, build just before transferring:

```powershell
.\build.ps1 -Device instinct2 -Release -TestAlarmMinutes 7
```

The script prints an absolute deadline seven minutes after the build starts.
Copy `bin/instinct2/JumpStart.prg` to the connected watch's `GARMIN/APPS/`, eject,
and open JumpStart before that deadline. That build arms the deadline once on
first launch. Reopening after dismissal does not rearm it. If transfer takes too
long, choose **Test in 5 min** on the watch instead. Normal builds never auto-arm.

macOS: `make build`, `make test`, `make install` (defaults to `DEVICE=instinct2`,
watch at `/Volumes/GARMIN`; override `SDK_DIR`, `KEY`, `WATCH` as needed).
