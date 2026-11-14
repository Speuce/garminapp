# Jumping Jack Counter

A Garmin Connect IQ watch app that counts jumping jacks from the wrist accelerometer.
Target device is the fenix 7 Pro (`fenix7pro`); data so far was gathered on an Instinct 2 (`instinct2`), left wrist.

While recording, the app saves a training activity whose FIT file contains the raw
accelerometer stream (via `SensorLogging`) and shows a live rep count. BACK adds a lap marker.

## Detector

`source/RepCounter.mc` smooths the accelerometer Y axis and counts a rep each time it rises
above +1000 mg and then falls below -400 mg. It was tuned on one recorded set of 20 normal jacks.
It does not yet reject wrist raises (5 raises counted as 5) or marching (1 false rep).

## Build, test and install

Requires Java, a Connect IQ SDK with the device packages, and a signing key (excluded from version control).

macOS (`Makefile`, defaults to `instinct2`; override with `DEVICE=fenix7pro`):

```sh
make build     # Build bin/JUMPING.prg
make test      # Run unit tests (simulator must be open: make simulator)
make install   # Copy to a USB-mounted watch at /Volumes/GARMIN, clean macOS ._ files, eject
```

Windows (fenix 7 Pro):

```powershell
.\build.ps1          # Build bin/JUMPING.prg
.\build.ps1 -Run     # Build and launch in the simulator
.\build.ps1 -Release # Build a release version
```

In VS Code, use **Run Jumping App** from Run and Debug (F5).

## Recordings

`recordings/` holds FIT files from the watch and `labels.csv` describing what each contains.
`tools/fit_fixture.py` turns a recording into a Monkey C test fixture:

```sh
python3 -m venv .venv && .venv/bin/pip install fitparse
.venv/bin/python tools/fit_fixture.py recordings/<file>.fit <CONSTANT_NAME> > test/<Name>.mc
```

On the Instinct 2, accelerometer sample timestamps in the FIT file are invalid; use message
order (25 samples per message, about 25-26 Hz). Lap markers lag the sensor data by 1-2 s.
