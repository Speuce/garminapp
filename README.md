# Jumping Jack Counter

A Garmin Connect IQ watch app that counts jumping jacks from the wrist accelerometer.
Target device is the fenix 7 Pro (`fenix7pro`); data so far was gathered on an Instinct 2 (`instinct2`), left wrist.

While recording, the app saves a training activity whose FIT file contains the raw
accelerometer stream (via `SensorLogging`) and shows a live rep count. BACK adds a lap marker.

## Detector

`source/RepCounter.mc` runs the adaptive detector on the watch. Each callback feeds
calibrated X/Y/Z samples in order at the requested 25 Hz. The counter smooths all
three axes, finds candidate movements from a rise and a return relative to the
current peak, and checks movement duration, X/Z range, vector magnitude and shape.
Candidate timeouts and repetition spacing adapt to the observed cadence.

Three qualifying cycles confirm a run; the initial count then advances by three.
Subsequent qualifying cycles add one. Pauses clear pending confirmation, and the
last three accepted movement scores set the continuation strength threshold.
The first 20 samples estimate resting gravity only when they appear stationary;
otherwise the counter keeps the nominal milli-g scale. All state has fixed size,
with no per-sample arrays or growing sample history.

The checked-in Monkey C simulator tests replay both labelled XYZ recordings:
20/20 normal jacks and zero counts for watch checks/marching. They also verify
the count increment at every sample against the reference, weak returns, changing
cadence, calibration, pauses and timeout recovery. These recordings cover one
left-wrist Instinct 2 user; they do not establish accuracy for every movement style.

## Build, test and install

Requires Java, a Connect IQ SDK with the device packages, and a signing key (excluded from version control).

macOS (`Makefile`, defaults to `instinct2`; override with `DEVICE=fenix7pro`):

```sh
make build     # Build bin/JUMPING.prg
make test      # Run unit tests (simulator must be open: make simulator)
make install   # Copy to a USB-mounted watch at /Volumes/GARMIN, clean macOS ._ files, eject
```

Windows (defaults to fenix 7 Pro; builds into `bin/<device>/`):

```powershell
.\build.ps1          # Build bin/fenix7pro/JUMPING.prg
.\build.ps1 -Run     # Build and launch in the simulator
.\build.ps1 -Release # Build a release version
.\build.ps1 -Test    # Run the Monkey C simulator tests
.\build.ps1 -Device instinct2 -Test
.\build.ps1 -Device instinct2 -Run
```

Use `-Key <path>` if the signing key is outside this checkout. `-TestName <name>`
with `-Test` runs an individual test. The script checks the simulator's test summary
and saves it as `bin/<device>/test-results.txt`.

In VS Code, use **Run Jumping App** from Run and Debug (F5).

## Recordings

`recordings/` holds FIT files from the watch and `labels.csv` describing what each contains.
`test/RecordedSamples.mc` contains the labelled recordings as flattened XYZ triples,
in small blocks to stay within SDK compiler limits. Test fixtures are excluded from
production builds. Python analysis and cross-language validation tools remain local;
Python is not required to build, test in Connect IQ, or run the watch app.

On the Instinct 2, accelerometer sample timestamps in the FIT file are invalid; use message
order (25 samples per message, about 25-26 Hz). Lap markers lag the sensor data by 1-2 s.
