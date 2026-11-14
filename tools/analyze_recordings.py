"""Replay the current detector and inspect calibrated XYZ data in local FIT files.

Install: python -m pip install fitparse numpy matplotlib
Run from the repository root: python tools/analyze_recordings.py
Outputs go to build/analysis by default. No watch code or recordings are modified.

Sensor timestamps in these recordings are invalid. All calculations use file
sample order; seconds assume 25 Hz and lap sample positions are approximate.
Threshold/timeout comparisons are exploratory fits to these recordings, not
validation on independent data. The timeout comparison rejects completed
candidates longer than 30 samples; it is not a new production state machine.
"""

import argparse
import csv
import json
from collections import Counter
from pathlib import Path

import fitparse
import numpy as np


def read_recording(path):
    xyz, laps, times, block_sizes = [], [], [], []
    duration = None
    types = Counter()
    # Exhaust the reader so that the FIT CRC is checked, including the footer.
    for message in fitparse.FitFile(str(path), check_crc=True).get_messages():
        types[message.name] += 1
        if message.name == "accelerometer_data":
            axes = [message.get_value("calibrated_accel_" + axis) for axis in "xyz"]
            if any(axis is None for axis in axes) or len({len(axis) for axis in axes}) != 1:
                raise ValueError(f"Missing or unequal calibrated XYZ arrays: {path}")
            block = np.array(axes, dtype=float).T
            if not np.isfinite(block).all():
                raise ValueError(f"Invalid calibrated acceleration: {path}")
            xyz.extend(block)
            block_sizes.append(len(block))
            times.append(str(message.get_value("timestamp")))
        elif message.name == "lap":
            laps.append({
                "index": message.get_value("message_index"),
                "samples_seen_in_file": len(xyz),
                "elapsed_seconds": message.get_value("total_elapsed_time"),
                "trigger": message.get_value("lap_trigger"),
            })
        elif message.name == "session":
            duration = message.get_value("total_elapsed_time")
    if not xyz:
        raise ValueError(f"No accelerometer samples: {path}")
    return np.array(xyz), {
        "file": path.name,
        "sample_count": len(xyz),
        "session_seconds": duration,
        "block_sizes": dict(Counter(block_sizes)),
        "unique_sensor_message_timestamps": len(set(times)),
        "message_types": dict(types),
        "laps": laps,
    }


def smooth(y):
    # Float32 mirrors Monkey C Float arithmetic, including operation order.
    values = np.asarray(y, dtype=np.float32)
    filtered = np.empty_like(values)
    filtered[0] = values[0]
    for i in range(1, len(values)):
        filtered[i] = filtered[i - 1] + np.float32(0.3) * (values[i] - filtered[i - 1])
    return filtered


def candidates(filtered, high=1000, low=-400):
    armed = None
    result = []
    for i, value in enumerate(filtered):
        if armed is None and value > high:
            armed = i
        elif armed is not None and value < low:
            result.append((armed, i))
            armed = None
    return result


def feature_rows(xyz, filtered, events, hz):
    rows = []
    previous = None
    for high, low in events:
        magnitude = np.linalg.norm(xyz[high:low + 1], axis=1)
        rows.append({
            "high_sample": high,
            "low_sample": low,
            "high_to_low_samples": low - high,
            "high_to_low_seconds_approx": round((low - high) / hz, 3),
            "rep_interval_seconds_approx": None if previous is None else round((low - previous) / hz, 3),
            "peak_smoothed_y_mg": round(float(filtered[high:low + 1].max()), 2),
            "peak_vector_magnitude_mg": round(float(magnitude.max()), 2),
            "minimum_vector_magnitude_mg": round(float(magnitude.min()), 2),
        })
        previous = low
    return rows


def write_csv(path, fieldnames, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def plot_recordings(recordings, output, hz):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    labels = {
        "2026-11-14-12-09-05.fit": "Unlabelled pipeline recording",
        "2026-11-14-12-20-46.fit": "20 labelled jumping jacks",
        "2026-11-14-12-37-27.fit": "Watch checks, then marching (0 jacks)",
    }
    fig, axes = plt.subplots(len(recordings), 2, figsize=(15, 3.2 * len(recordings)), squeeze=False)
    for row, (xyz, filtered, events, meta) in enumerate(recordings):
        t = np.arange(len(xyz)) / hz
        left, right = axes[row]
        left.plot(t, xyz[:, 1] / 1000, color="#c7d7e6", linewidth=0.7, label="Raw Y")
        left.plot(t, filtered / 1000, color="#2464a4", linewidth=1.3, label="Smoothed Y")
        left.axhline(1, color="#b05c1b", linestyle="--", linewidth=1, label="High / low thresholds")
        left.axhline(-0.4, color="#b05c1b", linestyle="--", linewidth=1)
        for j, (high, low) in enumerate(events):
            left.axvspan(high / hz, low / hz, color="#f3a04d", alpha=0.13)
            left.scatter(low / hz, filtered[low] / 1000, s=22, color="#b7293b", zorder=5,
                         label="Count increment" if j == 0 else None)
        left.set_title(f"{labels.get(meta['file'], meta['file'])} | counted {len(events)}", loc="left", fontsize=11)
        left.set_ylabel("Y acceleration (g)")
        right.plot(t, np.linalg.norm(xyz, axis=1) / 1000, color="#258476", linewidth=0.9)
        right.axhline(1, color="#9eabb4", linestyle="--", linewidth=1)
        right.set_title("Combined X/Y/Z magnitude", loc="left", fontsize=11)
        right.set_ylabel("Magnitude (g)")
        for ax in (left, right):
            for lap in meta["laps"]:
                if lap["trigger"] == "manual":
                    ax.axvline(lap["samples_seen_in_file"] / hz, color="#777777", linestyle=":", linewidth=1)
            ax.set_xlim(0, t[-1])
            ax.set_xlabel("Approximate seconds (sample index / 25 Hz)")
            ax.grid(alpha=0.16)
            ax.spines[["top", "right"]].set_visible(False)
        if row == 0:
            left.legend(loc="upper right", fontsize=8, ncol=2)
    fig.suptitle("Current detector replay: a Y threshold sequence is not unique to jumping jacks", x=0.065, ha="left", fontsize=15)
    fig.text(0.065, 0.015, "Shading = detector armed. Dotted lines = lap records in file order (approximate). Sensor timestamps are invalid.", fontsize=10, color="#505961")
    fig.tight_layout(rect=(0.01, 0.035, 1, 0.96))
    fig.savefig(output / "recording_comparison.png", dpi=150)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recordings", type=Path, default=Path("recordings"))
    parser.add_argument("--output", type=Path, default=Path("build/analysis"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    hz = 25.0
    recordings, summary, comparisons = [], [], []
    for path in sorted(args.recordings.glob("*.fit")):
        xyz, meta = read_recording(path)
        filtered = smooth(xyz[:, 1])
        events = candidates(filtered)
        features = feature_rows(xyz, filtered, events, hz)
        meta["baseline_count"] = len(events)
        meta["candidates"] = features
        meta["time_basis"] = "Sample order / assumed 25 Hz; approximate, not sensor timestamps"
        write_csv(args.output / (path.stem + "_samples.csv"),
                  ["sample", "approx_seconds", "x_mg", "y_mg", "z_mg", "smoothed_y_mg"],
                  ({"sample": i, "approx_seconds": i / hz, "x_mg": x, "y_mg": y,
                    "z_mg": z, "smoothed_y_mg": float(filtered[i])} for i, (x, y, z) in enumerate(xyz)))
        if features:
            write_csv(args.output / (path.stem + "_candidates.csv"), list(features[0]), features)
        for high in (1000, 1400, 1500, 1600, 1700, 1750, 1800, 2000):
            comparisons.append({"file": path.name, "experiment": f"high={high},low=-400", "count": len(candidates(filtered, high))})
        timeout_count = sum(low - high <= 30 for high, low in events)
        comparisons.append({"file": path.name, "experiment": "baseline candidates <=30 samples", "count": timeout_count})
        summary.append(meta)
        recordings.append((xyz, filtered, events, meta))
        print(f"{path.name}: {len(xyz)} XYZ samples, {meta['session_seconds']}s session, baseline={len(events)}, high1600={len(candidates(filtered, 1600))}, <=30samples={timeout_count}")
    if not recordings:
        parser.error("No FIT recordings found")
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    write_csv(args.output / "exploratory_comparisons.csv", ["file", "experiment", "count"], comparisons)
    plot_recordings(recordings, args.output, hz)
    print(f"Analysis written to {args.output.resolve()}")


if __name__ == "__main__":
    main()
