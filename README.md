# Empty App

A minimal Garmin Connect IQ watch app for the fenix 7 Pro (`fenix7pro`).
The app displays a blank black screen and requests no permissions.

## Build and run

Requires Java, a selected Connect IQ SDK with the `fenix7pro` device package,
and a signing key at `developer_key` (excluded from version control).

```powershell
.\build.ps1          # Build bin/EmptyApp.prg
.\build.ps1 -Run     # Build and launch in the simulator
.\build.ps1 -Release # Build a release version
```

In VS Code, use **Run Empty App** from Run and Debug (F5).

## Files

- `source/EmptyApp.mc`: app entry point.
- `source/EmptyView.mc`: blank view; start adding your UI here.
- `manifest.xml`: app identity and supported device.
- `resources/`: app name and launcher icon.
