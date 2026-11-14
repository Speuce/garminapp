# JumpStart

A Connect IQ alarm app for Instinct 2 (`instinct2`) and fenix 7 Pro (`fenix7pro`).
Saved alarms start a challenge that stops after 20 confirmed jumping jacks.

## On the watch

- UP/DOWN selects an alarm or **Add alarm**. START/GPS opens the editor.
- Set the hour, minute, AM/PM and repeat rule; confirm the review screen to save.
- Hold UP/MENU on an alarm for Edit, Enable/Disable, Delete, Add alarm, **Test now** or **Test in 5 min**.
- Hold UP/MENU on **Add alarm** for the test options, including when the list is empty.
- BACK steps through the editor; discarding a draft preserves the saved alarm.

Up to 16 alarms are stored and verified after writing. Repeat rules include daily,
weekdays, weekends, custom days every N weeks, every N days and a one-time date.
Intervals are anchored to the date in the alarm record; custom weeks start on Monday.

The earliest enabled alarm is scheduled whenever the list changes. The app checks
its schedule every second, including while editing another alarm. Closing and
reopening during the ten-minute ringing window preserves the pending alarm.
Completing a challenge reschedules repeating alarms and disables completed one-time
alarms. Alarms due together share a challenge. Test mode preserves saved alarms.

When JumpStart is open, ringing starts automatically. When it is closed, Garmin's
[background wake API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html#requestApplicationWake-instance_function)
shows a system prompt; accepting it opens the challenge. Connect IQ does not allow
this app to bypass that prompt. The background service registers the next occurrence
even if a prompt is ignored. Garmin requires five minutes between background runs,
so closely spaced alarms may be delayed outside the app. A failed registration
shows **Keep app open**; foreground timing continues to work.

Stand still briefly when ringing starts, then do jumping jacks. The counter confirms
three cycles before crediting the first three reps. Ordinary START/BACK presses
cannot dismiss a real alarm; BACK can cancel a preview or exit a reported sensor failure.
The sensor samples at 25 Hz only while the challenge is visible.

## Implementation and validation

`source/common/AlarmStore.mc` owns the persisted alarm list. `AlarmSchedule.mc`
calculates local calendar occurrences and preserves the selected occurrence across
launches. `JumpStartApp.mc` connects the editor, scheduler and challenge. Device-specific
Trail views handle the Instinct's subwindow and the fenix 7 Pro's 260px color screen.

`source/common/RepCounter.mc` is the adaptive X/Y/Z detector: smoothed axes,
peak-relative returns, adaptive cadence, X/Z span, magnitude and shape checks.
`AlarmChallenge.mc` wraps it with exact completion and late-callback protection.
Neither the detector nor the watch app requires Python.

The native simulator suite covers alarm editing, persistence, failed writes, capacity,
calendar rules, local-time conversion, leap years, list rescheduling, reopening a due
alarm, one-time completion, simultaneous alarms, test isolation and detector behavior.
The original recordings still produce 20/20 normal jacks and zero counts for watch
checks/marching. These recordings cover one left-wrist Instinct 2 user, not population-wide
accuracy. The full recordings are also checked sample by sample against reference counts.

`recordings/` contains the original FIT files and labels. `test/RecordedSamples.mc`
contains their XYZ samples and is excluded from normal builds. The original FIT
accelerometer timestamps/offsets are invalid. Local simulator copies in `build/alarm/`
reconstruct timing at 25 Hz without changing the XYZ values. Python analysis and
playback preparation stay local and are excluded from commits.

Integration validation (2026-11-14, SDK 9.1.0): all 31 native tests pass on both
devices. An alarm saved through the Instinct editor triggered the background wake
prompt at its scheduled minute after the app was closed. Accepting the prompt and
replaying the negative recording followed by the positive recording kept the count
at zero for the negative segment and dismissed the alarm at 20 jacks. A saved alarm
also triggered automatically in the foreground on fenix 7 Pro; its list, editor,
review and challenge layouts were inspected. The fenix simulator delivers generated
accelerometer samples, but did not deliver this FIT recording through its sensor
callback. Fenix recording validation therefore uses the native sample-by-sample
tests; full FIT playback and physical fenix validation remain unverified.

## Build and test

Requires Java, a selected Connect IQ SDK, installed device packages and a signing key
(excluded from Git). On Windows:

```powershell
.\build.ps1 -Device instinct2 -Run
.\build.ps1 -Device instinct2 -Test
.\build.ps1 -Device fenix7pro -Test
.\build.ps1 -Device instinct2 -Release
```

Use `-Key <path>` for a key outside this checkout and `-TestName <name>` to select a test.
Outputs are under `bin/<device>/`; test summaries are saved as `test-results.txt`.
The merged UI uses Monkey C's permissive type-checking level 1, with compiler warnings enabled.
`make build`, `make test` and `make install` are also available with configurable SDK,
device, key and watch paths.

A one-off sideload test can be compiled just before transfer:

```powershell
.\build.ps1 -Device instinct2 -Release -TestAlarmMinutes 7
```

This generates a local resource override with an absolute deadline. Copy
`bin/instinct2/JumpStart.prg` to the watch's `GARMIN/APPS/`, eject, and open JumpStart
before the deadline. Each deadline is applied once without replacing saved alarms.
Normal builds do not auto-arm a test. For repeatable hardware checks, use the watch's
**Test in 5 min** action or create an alarm in the editor.
