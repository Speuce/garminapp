"""Reproduce adaptive-detector validation without changing the old baseline.

Run from the repository root: .venv/Scripts/python.exe -B tools/validate_adaptive.py
The unchanged synthetic generator is tested with old and fresh seeds. Known
real recordings are regression checks, not an untouched human holdout.
"""

import hashlib
import html
import json
from pathlib import Path

import numpy as np

from adaptive_timed import config_dict, detect_adaptive
from analyze_recordings import read_recording, write_csv
from validate_detectors import (ACTIVE_INTERVAL, NEGATIVE_FILE, POSITIVE_FILE,
                                REFERENCES, classification_metrics, detect,
                                match_events, perturb, synthetic_session, window_rows)

KINDS = ("jack", "watch_check", "march", "twist", "arm_swing", "impulse", "idle")
METHODS = ("old_timed_xyz", "adaptive_xyz")
OUTPUT = Path("build/adaptive")


def run(xyz, method):
    return detect_adaptive(xyz) if method == "adaptive_xyz" else detect(xyz, "timed_xyz")


def synthetic_results(seed, sessions, label):
    rng = np.random.default_rng(seed)
    rows = []
    for kind in KINDS:
        totals = {m: dict(matched=0, missed=0, false_counts=0, error_sessions=0,
                          detected_sessions=0) for m in METHODS}
        for _ in range(sessions):
            xyz, refs = synthetic_session(rng, kind)
            for method in METHODS:
                ds = run(xyz, method)
                matches, missing, extras = match_events(ds, refs if kind == "jack" else [])
                t = totals[method]
                t["matched"] += len(matches)
                t["missed"] += len(missing)
                t["false_counts"] += len(extras)
                t["error_sessions"] += int(bool(extras) or bool(missing))
                t["detected_sessions"] += int(bool(ds))
        for method, t in totals.items():
            rows.append({"dataset": label, "seed": seed, "kind": kind, "method": method,
                         "sessions": sessions, "expected_reps": sessions * 8 if kind == "jack" else 0,
                         "rep_recall": t["matched"] / (sessions * 8) if kind == "jack" else None,
                         "session_rejection_rate": 1 - t["detected_sessions"] / sessions if kind != "jack" else None,
                         **t})
    return rows


def real_results():
    p, _ = read_recording(Path("recordings") / POSITIVE_FILE)
    n, _ = read_recording(Path("recordings") / NEGATIVE_FILE)
    rows, event_rows = [], []
    for method in METHODS:
        pd, nd = run(p, method), run(n, method)
        matches, missing, extras = match_events(pd, REFERENCES)
        metrics = {}
        for online in (False, True):
            windows = window_rows(p, pd, True, online=online) + window_rows(n, nd, False, online=online)
            score = classification_metrics([w["actual_jack_activity"] for w in windows],
                                           [w["predicted_jack_activity"] for w in windows])
            metrics["live_windows" if online else "credited_windows"] = score
        rows.append({"method": method, "matched_jacks": len(matches), "missed_jacks": len(missing),
                     "extra_positive_counts": len(extras), "negative_false_counts": len(nd),
                     "maximum_confirmation_delay_s": max((d.confirmed_at - d.sample) / 25 for d in pd) if pd else None,
                     **metrics})
        for file, ds in [(POSITIVE_FILE, pd), (NEGATIVE_FILE, nd)]:
            event_rows.extend({"method": method, "file": file, "sample": d.sample,
                               "confirmed_at": d.confirmed_at} for d in ds)
    return p, n, rows, event_rows


def stress_results(p, n, repeats=100):
    rng = np.random.default_rng(20261117)
    rows = []
    for scenario in ("noise_50mg", "gain_80_120pct", "bias_100mg", "rotation_15deg", "tempo_80_120pct", "combined"):
        totals = {m: dict(matched=0, missed=0, positive_extras=0, negative_false_counts=0,
                          negative_error_sessions=0) for m in METHODS}
        for _ in range(repeats):
            pp, scale = perturb(p, rng, scenario)
            nn, _ = perturb(n, rng, scenario)
            for method in METHODS:
                pd, nd = run(pp, method), run(nn, method)
                matches, missing, extras = match_events(pd, [round(r * scale) for r in REFERENCES],
                                                       max(8, round(12 * scale)))
                t = totals[method]
                t["matched"] += len(matches); t["missed"] += len(missing)
                t["positive_extras"] += len(extras); t["negative_false_counts"] += len(nd)
                t["negative_error_sessions"] += int(bool(nd))
        for method, t in totals.items():
            rows.append({"scenario": scenario, "method": method, "replays_per_recording": repeats,
                         "rep_recall": t["matched"] / (20 * repeats),
                         "rep_precision": t["matched"] / max(1, t["matched"] + t["positive_extras"] + t["negative_false_counts"]),
                         **t})
    return rows


def plot_results(synthetic, stress):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(11.5, 4.2))
    for ax, dataset, title in [(axes[0], "previous_test", "Previous generated test: jack recall"),
                               (axes[1], "fresh_test", "Fresh generated test: jack recall")]:
        values = [next(r["rep_recall"] for r in synthetic if r["dataset"] == dataset and r["kind"] == "jack" and r["method"] == m) for m in METHODS]
        ax.bar(["Old timed XYZ", "Adaptive XYZ"], np.array(values) * 100, color=["#b2bec9", "#158577"])
        ax.set_title(title, fontsize=10)
        for i, value in enumerate(values):
            ax.text(i, value * 100 + 2, f"{value:.1%}", ha="center")
    values = [next(r["rep_recall"] for r in stress if r["scenario"] == "combined" and r["method"] == m) for m in METHODS]
    axes[2].bar(["Old timed XYZ", "Adaptive XYZ"], np.array(values) * 100, color=["#b2bec9", "#158577"])
    axes[2].set_title("Perturbed real recordings: jack recall", fontsize=10)
    for i, value in enumerate(values):
        axes[2].text(i, value * 100 + 2, f"{value:.1%}", ha="center")
    for ax in axes:
        ax.axhline(90, color="#ad5b39", linestyle="--", linewidth=1)
        ax.set_ylim(0, 110); ax.set_ylabel("Percent")
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Adaptive timing and candidate detection", x=.06, ha="left")
    fig.text(.06, .025, "Fresh seed, unchanged synthetic generator. Real recordings remain known regression data.", fontsize=9)
    fig.tight_layout(rect=(0, .07, 1, .93))
    fig.savefig(OUTPUT / "comparison.png", dpi=160)
    plt.close(fig)


def report(real, synthetic, stress, passed):
    def table(headers, rows):
        return "<table><tr>" + "".join(f"<th>{html.escape(str(h))}</th>" for h in headers) + "</tr>" + "".join("<tr>" + "".join(f"<td>{html.escape(str(v))}</td>" for v in row) + "</tr>" for row in rows) + "</table>"
    real_table = table(["Method", "Real jacks / 20", "Extra counts in jack recording", "Negative false counts", "Live balanced accuracy"],
                       [[r["method"], r["matched_jacks"], r["extra_positive_counts"], r["negative_false_counts"], f"{r['live_windows']['balanced_accuracy']:.1%}"] for r in real])
    positive_table = table(["Dataset", "Method", "Matched", "Expected", "Recall", "False detections in positive sequences"],
                           [[r["dataset"], r["method"], r["matched"], r["expected_reps"], f"{r['rep_recall']:.2%}", r["false_counts"]] for r in synthetic if r["kind"] == "jack"])
    negative_table = table(["Fresh negative kind", "Method", "Sequences rejected", "Rejection rate", "False counts"],
                           [[r["kind"], r["method"], f"{r['sessions']-r['detected_sessions']}/{r['sessions']}", f"{r['session_rejection_rate']:.1%}", r["false_counts"]] for r in synthetic if r["dataset"] == "fresh_test" and r["kind"] != "jack"])
    stress_table = table(["Scenario", "Method", "Rep recall", "Rep precision", "False counts in negative replays"],
                        [[r["scenario"], r["method"], f"{r['rep_recall']:.2%}", f"{r['rep_precision']:.2%}", r["negative_false_counts"]] for r in stress])
    content = f"""<!doctype html><html lang="en"><meta charset="utf-8"><title>Adaptive detector validation</title>
<style>body{{font:16px/1.5 system-ui;max-width:1100px;margin:36px auto;padding:0 24px;color:#183040}}table{{border-collapse:collapse;width:100%;font-size:14px}}th,td{{text-align:left;padding:9px;border-bottom:1px solid #d9e1e8}}th{{background:#edf3f6}}h2{{margin-top:34px}}img{{max-width:100%}}</style>
<h1>Adaptive X/Y/Z detector validation</h1><p>Target passed: <b>{passed}</b>. The target requires at least 90% fresh synthetic rep recall, at least 90% rejection of sequences in every negative category, at least 90% synthetic detection precision, and exactly 20 real jacks with zero extra or negative counts.</p>
<h2>What changed</h2><ul><li>Peak-relative candidate completion replaces the mandatory -400 mg crossing, with a lower entry threshold and a minimum drop requirement.</li><li>Cadence is updated from accepted cycles; candidate expiration and acceptable inter-rep gaps follow this estimate, within hard limits.</li><li>Broad Y sweeps or stronger X/Z movement qualify a candidate. Starting a run requires three qualifying cycles; continuing strength thresholds track the last three accepted scores.</li><li>Twenty startup samples provide a gravity-scale estimate only if motion variance is low. Otherwise the nominal milli-g scale is retained. State and memory are bounded.</li></ul>
<h2>Real recordings</h2>{real_table}<p>Known regression data, not a new human test set. Event matching uses the same approximate reference positions and tolerance as the earlier analysis. Live activity scoring uses the same 14 positive and 27 negative two-second windows. Initial repetitions are back-credited after run confirmation.</p>
<h2>Generated positive sequences</h2>{positive_table}<img src="comparison.png" alt="Recall comparisons">
<h2>Fresh generated negative sequences</h2>{negative_table}
<h2>Perturbed real recordings</h2>{stress_table}<p>100 variants per original recording and scenario, using the previous noise, gain, offset, rotation and duration ranges. These variants reuse the original recordings and do not increase the number of independent human sessions.</p>
<h2>Protocol and limitations</h2><p>The synthetic generator was not changed. Development used seed 20261115 and known real regression/perturbation outcomes. The old test (20261116) is reported for comparison; a new seed (20261118) with 200 sequences per kind is used as the final synthetic test. No parameter changes should be made after observing this fresh test without retiring its holdout status. Synthetic success measures the assumed generator family, not all possible human movement.</p>
<p><a href="protocol.json">Configuration and hashes</a> · <a href="synthetic_results.csv">All generated results</a> · <a href="real_results.json">Real results</a> · <a href="real_events.csv">Real detections</a> · <a href="stress_results.csv">Stress results</a> · <a href="target_checks.json">Target checks</a></p>
<p>Reproduce: <code>.venv/Scripts/python.exe -B tools/validate_adaptive.py</code></p></html>"""
    (OUTPUT / "report.html").write_text(content, encoding="utf-8")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    protocol = {"config": config_dict(), "development_seed": 20261115,
                "previous_test_seed": 20261116, "fresh_test_seed": 20261118,
                "fresh_sessions_per_kind": 200, "development_sessions_per_kind": 120,
                "exposure": "Parameters developed using synthetic development and known real regression/stress data; fresh synthetic seed reserved until freeze.",
                "sample_rate_assumption_hz": 25,
                "hashes": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in
                           [Path("tools/adaptive_timed.py"), Path(__file__), Path("tools/validate_detectors.py")]}}
    # Write config/hash freeze before generating or scoring the fresh test.
    (OUTPUT / "protocol.json").write_text(json.dumps(protocol, indent=2), encoding="utf-8")
    p, n, real, events = real_results()
    print("Real recordings:", json.dumps(real), flush=True)
    (OUTPUT / "real_results.json").write_text(json.dumps(real, indent=2), encoding="utf-8")
    write_csv(OUTPUT / "real_events.csv", list(events[0]), events)
    synthetic = synthetic_results(20261115, 120, "development")
    synthetic += synthetic_results(20261116, 40, "previous_test")
    print("Running frozen fresh synthetic test...", flush=True)
    synthetic += synthetic_results(20261118, 200, "fresh_test")
    write_csv(OUTPUT / "synthetic_results.csv", list(synthetic[0]), synthetic)
    fresh = [r for r in synthetic if r["dataset"] == "fresh_test" and r["method"] == "adaptive_xyz"]
    print("Fresh synthetic results:", json.dumps(fresh), flush=True)
    positive = next(r for r in fresh if r["kind"] == "jack")
    real_new = next(r for r in real if r["method"] == "adaptive_xyz")
    precision = positive["matched"] / max(1, positive["matched"] + sum(r["false_counts"] for r in fresh))
    checks = {"synthetic_recall_at_least_90": positive["rep_recall"] >= .9,
              "each_negative_kind_at_least_90_rejected": all(r["session_rejection_rate"] >= .9 for r in fresh if r["kind"] != "jack"),
              "synthetic_precision_at_least_90": precision >= .9, "synthetic_precision": precision,
              "real_results_preserved": real_new["matched_jacks"] == 20 and real_new["extra_positive_counts"] == 0 and real_new["negative_false_counts"] == 0}
    passed = all(value for value in checks.values() if isinstance(value, bool))
    checks["all_targets_passed"] = passed
    (OUTPUT / "target_checks.json").write_text(json.dumps(checks, indent=2), encoding="utf-8")
    print("Running real-data perturbation regressions...", flush=True)
    stress = stress_results(p, n)
    write_csv(OUTPUT / "stress_results.csv", list(stress[0]), stress)
    plot_results(synthetic, stress)
    report(real, synthetic, stress, passed)
    print(json.dumps(checks), flush=True)
    print(f"Report: {(OUTPUT / 'report.html').resolve()}", flush=True)


if __name__ == "__main__":
    main()
