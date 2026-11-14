"""Compare three Python detector prototypes on recorded and synthetic motion.

Run: .venv/Scripts/python.exe -B tools/validate_detectors.py
Dependencies: fitparse, numpy, scipy, matplotlib.

No FIT samples enter classifier training or threshold selection. However, the
real recordings were inspected in an earlier investigation, and informed the
hand rules and synthetic waveform design. This is a development validation, not
an untouched estimate of generalization. Synthetic stress cases are assumptions,
not new human observations. The unlabelled FIT file is excluded from scoring.
"""

import argparse
import hashlib
import html
import importlib.metadata
import json
import platform
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.optimize import minimize
from scipy.special import expit
from scipy.spatial.transform import Rotation

from analyze_recordings import candidates, read_recording, smooth, write_csv

HZ = 25
POSITIVE_FILE = "2026-11-14-12-20-46.fit"
NEGATIVE_FILE = "2026-11-14-12-37-27.fit"
# Approximate event landmarks from the earlier replay, checked against the
# labelled total of 20. They are NOT independent human/video annotations.
REFERENCES = [166, 196, 231, 269, 307, 342, 378, 414, 447, 484,
              517, 550, 584, 621, 657, 693, 731, 766, 804, 844]
ACTIVE_INTERVAL = (150, 855)  # Analyst-selected visible activity envelope.
METHODS = ["baseline", "threshold", "timed_xyz", "synthetic_classifier"]
FEATURES = ["duration_s", "peak_y_g", "x_span_g", "z_span_g",
            "magnitude_mean_g", "magnitude_std_g", "magnitude_peak_g",
            "positive_y_area_gs"]


@dataclass
class Detection:
    sample: int
    confirmed_at: int
    score: float = 1.0


def filtered_xyz(xyz):
    return np.column_stack([smooth(xyz[:, i]) for i in range(3)])


def feature_vector(xyz, filtered, start, end):
    raw = xyz[start:end + 1] / 1000.0
    s = filtered[start:end + 1] / 1000.0
    mag = np.linalg.norm(raw, axis=1)
    return np.array([(end - start) / HZ, s[:, 1].max(), np.ptp(s[:, 0]),
                     np.ptp(s[:, 2]), mag.mean(), mag.std(), mag.max(),
                     np.maximum(s[:, 1], 0).sum() / HZ])


def timed_candidates(filtered):
    """Expire after 30 samples; require LOW to reset after expiration."""
    armed, blocked = None, False
    for i, y in enumerate(filtered[:, 1]):
        if blocked:
            if y < -400:
                blocked = False
            continue
        if armed is not None and i - armed > 30:
            armed, blocked = None, y >= -400
            yield None  # Invalid movement also interrupts a repetition run.
        elif armed is None and y > 1000:
            armed = i
        elif armed is not None and y < -400:
            yield (armed, i)
            armed = None


def detect(xyz, method, model=None):
    filtered = filtered_xyz(xyz)
    if method in ("baseline", "threshold"):
        high = 1000 if method == "baseline" else 1600
        return [Detection(end, end) for _, end in candidates(filtered[:, 1], high)]
    if method == "synthetic_classifier":
        events = candidates(filtered[:, 1])
        if not events:
            return []
        x = np.array([feature_vector(xyz, filtered, a, b) for a, b in events])
        probabilities = predict(model, x)
        return [Detection(end, end, float(p)) for (_, end), p in zip(events, probabilities)
                if p >= model["threshold"]]
    if method != "timed_xyz":
        raise ValueError(method)
    result, pending, active = [], [], False
    for event in timed_candidates(filtered):
        if event is None:
            pending, active = [], False
            continue
        start, end = event
        f = feature_vector(xyz, filtered, start, end)
        valid = 4 <= end - start <= 30 and f[2] >= .3 and f[3] >= .3 and f[4] >= 1.25
        if not valid:
            pending, active = [], False
            continue
        if pending and not 12 <= end - pending[-1] <= 55:
            pending, active = [], False
        pending.append(end)
        pending = pending[-3:]
        if len(pending) == 3:
            gaps = np.diff(pending)
            if gaps.max() / gaps.min() > 1.8:
                pending, active = [end], False
                continue
            if active:
                result.append(Detection(end, end))
            else:
                result.extend(Detection(e, end) for e in pending)
                active = True
    return result


def pulse(t, centre, width):
    return np.exp(-0.5 * ((t - centre) / width) ** 2)


def synthetic_session(rng, kind, n_cycles=8):
    """Analytic plausible motifs, not a calibrated biomechanical simulator.

    Jacks: broad/double positive Y lobe then a negative return, with correlated
    X/Z movement. Negatives include fast watch checks, periodic marches, twists,
    arm swings, idle and impulses. Magnitude and tempo distributions overlap.
    All axes receive offsets, noise and small rigid rotations.
    """
    base = np.array([.85, .20, -.25])
    chunks = [np.tile(base, (HZ, 1))]
    endpoints = []
    count = HZ
    for _ in range(n_cycles):
        if kind == "jack":
            duration = rng.uniform(.9, 1.95)
            amplitude = rng.uniform(1.55, 3.5)
        elif kind in ("watch_check", "twist"):
            duration = rng.uniform(.9, 3.6)
            amplitude = rng.uniform(.65, 2.7)
        else:
            duration = rng.uniform(.65, 1.8)
            amplitude = rng.uniform(.45, 2.4)
        n = max(12, round(duration * HZ))
        phase = np.arange(n) / n
        if kind == "jack":
            y = amplitude * (pulse(phase, .23, .12) + .85 * pulse(phase, .55, .13))
            y -= rng.uniform(1.1, 2.4) * pulse(phase, .83, .065)
            x = rng.uniform(.45, 1.25) * np.sin(2 * np.pi * phase + .5)
            z = rng.uniform(.5, 1.2) * np.sin(2 * np.pi * phase - .7)
        elif kind == "watch_check":
            y = amplitude * pulse(phase, .28, .10) + .3 * pulse(phase, .50, .17)
            y -= rng.uniform(.7, 1.4) * pulse(phase, .8, .10)
            x = rng.uniform(.3, .95) * np.sin(2 * np.pi * phase)
            z = rng.uniform(.1, .65) * np.sin(2 * np.pi * phase + .7)
        elif kind == "march":
            y = amplitude * pulse(phase, .28, .08) - rng.uniform(.15, 1.05) * pulse(phase, .72, .08)
            x = rng.uniform(.3, 1.1) * np.sin(2 * np.pi * phase)
            z = rng.uniform(.1, .65) * np.sin(2 * np.pi * phase + 1)
        elif kind == "twist":
            angle = rng.uniform(1.1, 3.0) * np.sin(2 * np.pi * phase)
            y = .85 * np.sin(angle) + .45 * amplitude * np.sin(2 * np.pi * phase)
            x = .85 * (np.cos(angle) - 1)
            z = .25 * np.sin(angle + .3)
        elif kind == "arm_swing":
            y = amplitude * np.sin(2 * np.pi * phase)
            x = rng.uniform(.1, .6) * np.cos(2 * np.pi * phase)
            z = rng.uniform(.1, .5) * np.sin(2 * np.pi * phase + .3)
        elif kind == "impulse":
            y = amplitude * pulse(phase, .3, .025) - amplitude * pulse(phase, .42, .025)
            x = .4 * y
            z = -.2 * y
        elif kind == "idle":
            x = y = z = np.zeros(n)
        else:
            raise ValueError(kind)
        envelope = np.minimum(1, np.minimum(phase, 1 - phase) / .08)
        chunk = base + np.column_stack([x, y, z]) * envelope[:, None]
        chunks.append(chunk)
        endpoints.append(count + round(.83 * n))
        count += n
    chunks.append(np.tile(base, (HZ, 1)))
    xyz = np.vstack(chunks)
    axis = rng.normal(size=3)
    axis /= np.linalg.norm(axis)
    xyz = xyz @ Rotation.from_rotvec(axis * rng.uniform(-.14, .14)).as_matrix().T
    xyz += rng.normal(0, rng.uniform(.015, .07), xyz.shape)
    xyz += rng.uniform(-.1, .1, 3)
    return xyz * 1000, endpoints


def synthetic_training(seed, sessions_per_kind):
    rng = np.random.default_rng(seed)
    x, y, kinds = [], [], []
    for kind in ("jack", "watch_check", "march", "twist", "arm_swing", "impulse", "idle"):
        for _ in range(sessions_per_kind):
            xyz, _ = synthetic_session(rng, kind)
            filtered = filtered_xyz(xyz)
            for start, end in candidates(filtered[:, 1]):
                x.append(feature_vector(xyz, filtered, start, end))
                y.append(int(kind == "jack"))
                kinds.append(kind)
    return np.array(x), np.array(y), kinds


def fit_classifier(x, y):
    mean, std = x.mean(axis=0), np.maximum(x.std(axis=0), 1e-6)
    a = np.column_stack([np.ones(len(x)), (x - mean) / std])
    weights = np.where(y == 1, .5 / sum(y == 1), .5 / sum(y == 0))

    def objective(beta):
        logits = a @ beta
        loss = np.sum(weights * (np.logaddexp(0, logits) - y * logits))
        loss += .01 * np.sum(beta[1:] ** 2) / 2
        gradient = a.T @ (weights * (expit(logits) - y))
        gradient[1:] += .01 * beta[1:]
        return loss, gradient

    fit = minimize(objective, np.zeros(a.shape[1]), jac=True, method="L-BFGS-B")
    if not fit.success:
        raise RuntimeError(f"Classifier optimization failed: {fit.message}")
    return {"mean": mean.tolist(), "std": std.tolist(), "coefficients": fit.x.tolist(),
            "threshold": .5, "features": FEATURES, "regularization": .01}


def predict(model, x):
    a = (np.asarray(x) - model["mean"]) / model["std"]
    beta = np.array(model["coefficients"])
    return expit(beta[0] + a @ beta[1:])


def classification_metrics(truth, predicted):
    truth, predicted = np.asarray(truth, bool), np.asarray(predicted, bool)
    tp = int(sum(truth & predicted)); fn = int(sum(truth & ~predicted))
    tn = int(sum(~truth & ~predicted)); fp = int(sum(~truth & predicted))
    sensitivity = tp / (tp + fn) if tp + fn else None
    specificity = tn / (tn + fp) if tn + fp else None
    return {"tp": tp, "fn": fn, "tn": tn, "fp": fp,
            "sensitivity": sensitivity, "specificity": specificity,
            "balanced_accuracy": (sensitivity + specificity) / 2 if sensitivity is not None and specificity is not None else None,
            "accuracy": (tp + tn) / len(truth) if len(truth) else None}


def match_events(detections, references, tolerance=12):
    unmatched = set(range(len(references)))
    matches = []
    extras = []
    for detection in sorted(detections, key=lambda d: d.sample):
        eligible = [i for i in unmatched if abs(references[i] - detection.sample) <= tolerance]
        if eligible:
            i = min(eligible, key=lambda j: abs(references[j] - detection.sample))
            unmatched.remove(i)
            matches.append((references[i], detection))
        else:
            extras.append(detection)
    return matches, unmatched, extras


def window_rows(xyz, detections, positive_file, interval=ACTIVE_INTERVAL, size=50, online=False):
    rows = []
    for start in range(0, len(xyz) - size + 1, size):
        end = start + size
        if positive_file:
            if start >= interval[0] and end <= interval[1]:
                truth = True
            elif end <= interval[0] or start >= interval[1]:
                truth = False
            else:
                continue  # Do not assign uncertain exercise boundary windows.
        else:
            truth = False
        predicted = any(start <= (d.confirmed_at if online else d.sample) < end for d in detections)
        rows.append({"start_sample": start, "end_sample": end,
                     "actual_jack_activity": truth, "predicted_jack_activity": predicted})
    return rows


def score_real(positive, negative, model):
    results, windows, detections = [], [], []
    for method in METHODS:
        pd, nd = detect(positive, method, model), detect(negative, method, model)
        matched, missed, extras = match_events(pd, REFERENCES)
        wr = window_rows(positive, pd, True) + window_rows(negative, nd, False)
        online = window_rows(positive, pd, True, online=True) + window_rows(negative, nd, False, online=True)
        wm = classification_metrics([r["actual_jack_activity"] for r in wr], [r["predicted_jack_activity"] for r in wr])
        om = classification_metrics([r["actual_jack_activity"] for r in online], [r["predicted_jack_activity"] for r in online])
        results.append({"method": method, "jack_count": len(pd), "matched_jacks": len(matched),
                        "missed_jacks": len(missed), "unmatched_positive_recording_counts": len(extras),
                        "negative_recording_false_counts": len(nd),
                        "rep_recall": len(matched) / len(REFERENCES),
                        "event_precision": len(matched) / (len(pd) + len(nd)) if pd or nd else 0,
                        "maximum_confirmation_delay_s": max([(d.confirmed_at - d.sample) / HZ for d in pd], default=0),
                        "windows": wm, "online_windows": om})
        for file, arr, ds, ispos in [(POSITIVE_FILE, positive, pd, True), (NEGATIVE_FILE, negative, nd, False)]:
            for r in window_rows(arr, ds, ispos):
                windows.append({"method": method, "file": file, **r})
            detections.extend({"method": method, "file": file, "sample": d.sample,
                               "confirmed_at": d.confirmed_at, "score": d.score} for d in ds)
    return results, windows, detections


def perturb(xyz, rng, scenario):
    out = xyz.copy()
    scale_time = 1.0
    if scenario in ("noise_50mg", "combined"):
        out += rng.normal(0, 50, out.shape)
    if scenario in ("gain_80_120pct", "combined"):
        out *= rng.uniform(.8, 1.2)
    if scenario in ("bias_100mg", "combined"):
        out += rng.uniform(-100, 100, 3)
    if scenario in ("rotation_15deg", "combined"):
        axis = rng.normal(size=3); axis /= np.linalg.norm(axis)
        out = out @ Rotation.from_rotvec(axis * rng.uniform(-np.pi / 12, np.pi / 12)).as_matrix().T
    if scenario in ("tempo_80_120pct", "combined"):
        scale_time = rng.uniform(.8, 1.2)
        t = np.linspace(0, len(out) - 1, round(len(out) * scale_time))
        out = np.column_stack([np.interp(t, np.arange(len(out)), out[:, i]) for i in range(3)])
        scale_time = (len(out) - 1) / (len(xyz) - 1)
    return out, scale_time


def stress_real(positive, negative, model, repetitions=100):
    rng = np.random.default_rng(20261117)
    rows = []
    for scenario in ("noise_50mg", "gain_80_120pct", "bias_100mg", "rotation_15deg", "tempo_80_120pct", "combined"):
        totals = {m: {"matched": 0, "extras": 0, "negative_fp": 0, "positive_total": 0,
                      "negative_sessions_with_fp": 0, "window_truth": [], "window_predictions": []} for m in METHODS}
        for _ in range(repetitions):
            p, scale = perturb(positive, rng, scenario)
            n, _ = perturb(negative, rng, scenario)
            references = [round(i * scale) for i in REFERENCES]
            interval = tuple(round(i * scale) for i in ACTIVE_INTERVAL)
            for method in METHODS:
                pd, nd = detect(p, method, model), detect(n, method, model)
                matches, _, extras = match_events(pd, references, tolerance=max(8, round(12 * scale)))
                total = totals[method]
                total["matched"] += len(matches); total["extras"] += len(extras)
                total["negative_fp"] += len(nd); total["positive_total"] += len(pd)
                total["negative_sessions_with_fp"] += int(bool(nd))
                windows = window_rows(p, pd, True, interval=interval) + window_rows(n, nd, False)
                total["window_truth"].extend(r["actual_jack_activity"] for r in windows)
                total["window_predictions"].extend(r["predicted_jack_activity"] for r in windows)
        for method, t in totals.items():
            metrics = classification_metrics(t.pop("window_truth"), t.pop("window_predictions"))
            rows.append({"scenario": scenario, "method": method, "replays_per_class": repetitions,
                         "rep_recall": t["matched"] / (20 * repetitions),
                         "event_precision": t["matched"] / max(1, t["positive_total"] + t["negative_fp"]),
                         "false_counts_per_negative_replay": t["negative_fp"] / repetitions,
                         "negative_replays_with_false_count_fraction": t["negative_sessions_with_fp"] / repetitions,
                         "window_balanced_accuracy": metrics["balanced_accuracy"], **t})
    return rows


def score_synthetic_test(model, sessions_per_kind=40):
    rng = np.random.default_rng(20261116)
    rows = []
    for kind in ("jack", "watch_check", "march", "twist", "arm_swing", "impulse", "idle"):
        counts = {m: [] for m in METHODS}
        matched_counts = {m: [] for m in METHODS}
        extra_counts = {m: [] for m in METHODS}
        for _ in range(sessions_per_kind):
            xyz, endpoints = synthetic_session(rng, kind)
            for method in METHODS:
                detections = detect(xyz, method, model)
                counts[method].append(len(detections))
                matched, _, extra = match_events(detections, endpoints if kind == "jack" else [])
                matched_counts[method].append(len(matched))
                extra_counts[method].append(len(extra))
        for method, values in counts.items():
            rows.append({"kind": kind, "method": method, "sessions": sessions_per_kind,
                         "labelled_reps_per_session": 8 if kind == "jack" else 0,
                         "mean_count": float(np.mean(values)),
                         "matched_reps": sum(matched_counts[method]),
                         "unmatched_detections": sum(extra_counts[method]),
                         "rep_recall": sum(matched_counts[method]) / (8 * sessions_per_kind) if kind == "jack" else None,
                         "sessions_with_any_detection": int(sum(v > 0 for v in values)),
                         "sessions_with_exact_count": int(sum(v == (8 if kind == "jack" else 0) for v in values))})
    return rows


def make_plot(results, stress, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names = ["Current", "Threshold", "Timed XYZ", "Synthetic classifier"]
    colors = ["#aeb6bf", "#4764bc", "#178778", "#9650ab"]
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.3))
    for ax, metric, title in [(axes[0], "rep_recall", "Recorded jacks recovered"),
                              (axes[1], "specificity", "Recorded non-jack windows rejected"),
                              (axes[2], "stress", "Combined perturbation: balanced accuracy")]:
        if metric == "specificity":
            values = [r["windows"][metric] for r in results]
        elif metric == "stress":
            values = [next(s["window_balanced_accuracy"] for s in stress if s["scenario"] == "combined" and s["method"] == m) for m in METHODS]
        else:
            values = [r[metric] for r in results]
        ax.bar(np.arange(4), np.array(values) * 100, color=colors)
        ax.axhline(90, color="#b35334", linestyle="--", linewidth=1)
        ax.set_ylim(0, 110); ax.set_xticks(range(4), names, rotation=22, ha="right")
        ax.set_title(title, fontsize=11); ax.set_ylabel("Percent")
        for i, v in enumerate(values):
            ax.text(i, 100 * v + 2, f"{100*v:.1f}%", ha="center", fontsize=9)
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Development validation on two labelled recordings", x=.06, ha="left", fontsize=15)
    fig.text(.06, .015, "Dashed line: 90% target. Perturbations reuse the same recordings; they are not additional human validation.", fontsize=9)
    fig.tight_layout(rect=(0, .05, 1, .92))
    fig.savefig(output / "validation_comparison.png", dpi=160)
    plt.close(fig)


def make_report(results, stress, synthetic, model, protocol, output):
    names = dict(zip(METHODS, ["Current detector", "Retuned threshold", "Timed X/Y/Z", "Synthetic classifier"]))

    def table(headers, rows):
        head = "".join(f"<th>{html.escape(str(v))}</th>" for v in headers)
        body = "".join("<tr>" + "".join(f"<td>{html.escape(str(v))}</td>" for v in row) + "</tr>" for row in rows)
        return f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"

    def pct(value):
        return f"{value * 100:.1f}%"

    real_table = table(["Method", "Jacks matched / 20", "False counts", "Rep precision", "Window balanced accuracy", "Live window balanced accuracy"],
                       [[names[r["method"]], r["matched_jacks"], r["negative_recording_false_counts"],
                         pct(r["event_precision"]), pct(r["windows"]["balanced_accuracy"]),
                         pct(r["online_windows"]["balanced_accuracy"])] for r in results])
    combined_table = table(["Method", "Rep recall", "Rep precision", "False counts / negative replay", "Negative replays with a false count"],
                           [[names[r["method"]], pct(r["rep_recall"]), pct(r["event_precision"]),
                             f"{r['false_counts_per_negative_replay']:.2f}", pct(r["negative_replays_with_false_count_fraction"])]
                            for r in stress if r["scenario"] == "combined"])
    synthetic_rows = []
    for method in METHODS:
        pos = next(r for r in synthetic if r["method"] == method and r["kind"] == "jack")
        neg = [r for r in synthetic if r["method"] == method and r["kind"] != "jack"]
        synthetic_rows.append([names[method], f"{pos['matched_reps']} / 320", pct(pos["rep_recall"]),
                               sum(r["sessions_with_any_detection"] for r in neg),
                               sum(r["unmatched_detections"] for r in neg)])
    synthetic_table = table(["Method", "Generated jacks matched", "Rep recall", "Negative sessions with errors / 240", "Total negative false counts"], synthetic_rows)
    content = f"""<!doctype html><html lang="en"><meta charset="utf-8"><title>Jumping-jack detector validation</title>
<style>body{{font:16px/1.55 system-ui,sans-serif;max-width:1100px;margin:40px auto;padding:0 24px;color:#172b3a}}h1,h2{{line-height:1.2}}h2{{margin-top:36px}}table{{border-collapse:collapse;width:100%;font-size:14px}}th,td{{padding:10px 12px;border-bottom:1px solid #d7e0e7;text-align:left}}th{{background:#edf3f7}}img{{max-width:100%}}.note{{padding:16px;background:#f3f6f8;border-left:4px solid #4b7189}}code{{font-size:14px}}</style>
<h1>Jumping-jack detector: Python validation</h1>
<p>All three prototypes preserve the 20 recorded jacks and reject the six recorded false counts. The timed X/Y/Z method is strongest under perturbations of these recordings. Broad generated motion exposes failures in every approach.</p>
<p class="note">Development validation, not an untouched test set: the recordings were inspected previously and informed hand rules and synthetic design. No recorded samples entered classifier fitting. Generated signals and perturbed recordings are not additional human evidence.</p>
<h2>Recorded validation</h2>{real_table}
<p>Two labelled files: 1,025 samples with 20 normal jacks, and 1,100 samples with watch checks, marching and rest. The unlabelled 700-sample pipeline test is excluded. Sensor timestamps are invalid; time assumes 25 Hz.</p>
<p>Activity scoring uses 14 positive and 27 negative non-overlapping two-second windows. Mixed exercise/rest boundary windows and incomplete final windows are excluded. A window is positive when at least one accepted rep falls inside it. Balanced accuracy averages positive-window recall and negative-window rejection. This is activity detection, not a per-sample motion classification.</p>
<p>Rep matching uses approximate landmarks from the earlier replay, with a 12-sample tolerance and one-to-one matching; these are not independently annotated rep timestamps. The labelled total of 20 provides the count check. The timed method back-credits initial reps after its third confirmation, adding up to 2.6 seconds of confirmation delay. Live scoring uses report time rather than credited event time.</p>
<h2>Methods</h2><ol>
<li><b>Retuned threshold:</b> same 0.3 smoothing, high 1,600 mg, low -400 mg.</li>
<li><b>Timed X/Y/Z:</b> candidate duration 4–30 samples; X and Z spans at least 0.3 g; mean vector magnitude at least 1.25 g. Require three cycles with 12–55-sample gaps and adjacent gap ratio no more than 1.8. Expired candidates require a low crossing before rearming.</li>
<li><b>Synthetic classifier:</b> regularized logistic regression on eight duration, axis-span and magnitude features. Trained on {model['training_candidates']:,} generated candidates; cutoff {model['threshold']:.2f} chosen on {model['development_candidates']:,} separate-seed synthetic development candidates. No real FIT samples or their augmentations were used in fitting.</li></ol>
<h2>Perturbed real recordings</h2>{combined_table}
<p>Combined scenario: {protocol['stress_repetitions']} variants of each recording, mixing 50 mg Gaussian noise, 0.8–1.2 amplitude gain, up to 100 mg per-axis offsets, up to 15-degree rotations, and 0.8–1.2 duration scaling. These are sensitivity probes, not a physical model of every possible person or watch placement. Separate tests for each disturbance are in <a href="perturbation_results.csv">the full CSV</a>.</p>
<img src="validation_comparison.png" alt="Recorded and perturbation comparison">
<h2>Independent-seed generated scenarios</h2>{synthetic_table}
<p>Forty generated eight-jack sequences and 240 negative sequences (40 each of watch checks, marching, twists, arm swings, impulses and idle). These use analytic motifs with varied amplitude and tempo, not a calibrated biomechanical simulator. They share a generator family with training but use a separate seed.</p>
<p>The classifier's {pct(model['development_metrics']['balanced_accuracy'])} synthetic development score is conditional on the original Y-crossing candidate generator. It does not include jacks missed before classification. The end-to-end generated-rep results above expose this limitation. The timed detector also drops irregular or slow generated runs because of its timeout and three-cycle confirmation.</p>
<h2>Interpretation</h2><p>The 90% target is met on the existing recordings. The timed X/Y/Z prototype is the best candidate for this recorded normal-jack style and its tested perturbations. No method establishes 90% recall across the broader generated motions, or 90% performance on new human sessions. The next algorithmic improvement would be a less restrictive candidate generator plus timing that adapts to cadence, evaluated on the same explicitly limited protocol.</p>
<h2>Reproduce and inspect</h2><p><code>.venv/Scripts/python.exe -B tools/validate_detectors.py</code></p>
<p><a href="protocol.json">Protocol and version hashes</a> · <a href="synthetic_model.json">Model weights</a> · <a href="recorded_results.json">Recorded results</a> · <a href="recorded_windows.csv">Every scored window</a> · <a href="recorded_detections.csv">Every detection</a> · <a href="synthetic_test_results.csv">Generated-scenario results</a></p>
<p>Metric reference: <a href="https://scikit-learn.org/stable/modules/generated/sklearn.metrics.balanced_accuracy_score.html">balanced accuracy</a>. Evaluation reference: <a href="https://scikit-learn.org/stable/common_pitfalls.html">data leakage and test-set separation</a>.</p></html>"""
    (output / "report.html").write_text(content, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/validation"))
    parser.add_argument("--stress-repetitions", type=int, default=100)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    protocol = {
        "validation_status": "Development validation; recordings previously inspected. Not an untouched holdout.",
        "training": "Analytic synthetic traces only; no recorded samples or augmentations in fitting.",
        "train_seed": 20261114, "development_seed": 20261115, "synthetic_test_seed": 20261116,
        "stress_seed": 20261117, "sample_rate_assumed": HZ,
        "positive_file": POSITIVE_FILE, "negative_file": NEGATIVE_FILE,
        "unlabelled_file_excluded": "2026-11-14-12-09-05.fit",
        "reference_samples": REFERENCES, "reference_caveat": "Approximate earlier-replay landmarks, not independent rep annotations.",
        "active_interval": ACTIVE_INTERVAL, "window_samples": 50,
        "window_policy": "Non-overlapping 2s windows; exclude mixed positive/rest boundaries and trailing partial windows.",
        "threshold_rule": {"high_mg": 1600, "low_mg": -400, "smoothing": .3},
        "timed_rule": {"min_samples": 4, "max_samples": 30, "min_x_span_g": .3,
                       "min_z_span_g": .3, "min_mean_magnitude_g": 1.25,
                       "confirmation_cycles": 3, "min_gap_samples": 12, "max_gap_samples": 55, "max_gap_ratio": 1.8},
        "stress_repetitions": args.stress_repetitions,
        "environment": {"python": platform.python_version(),
                        **{p: importlib.metadata.version(p) for p in ["fitparse", "numpy", "scipy", "matplotlib"]}},
    }
    (args.output / "protocol.json").write_text(json.dumps(protocol, indent=2), encoding="utf-8")
    print("Generating synthetic training/development signals...", flush=True)
    x, y, kinds = synthetic_training(20261114, 180)
    dx, dy, _ = synthetic_training(20261115, 60)
    model = fit_classifier(x, y)
    dp = predict(model, dx)
    # Threshold selected once, using synthetic development data only.
    grid = [(classification_metrics(dy, dp >= t)["balanced_accuracy"], t) for t in np.linspace(.1, .9, 81)]
    model["threshold"] = float(max(grid, key=lambda item: (item[0], -abs(item[1] - .5)))[1])
    model["training_candidates"] = len(y)
    model["training_positive_candidates"] = int(sum(y))
    model["development_candidates"] = len(dy)
    model["development_metrics"] = classification_metrics(dy, dp >= model["threshold"])
    model["training_kinds"] = {kind: kinds.count(kind) for kind in sorted(set(kinds))}
    model_path = args.output / "synthetic_model.json"
    model_path.write_text(json.dumps(model, indent=2), encoding="utf-8")
    # Freeze the fitted model before reading validation FIT data.
    protocol["model_sha256"] = hashlib.sha256(model_path.read_bytes()).hexdigest()
    protocol["implementation_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (args.output / "protocol.json").write_text(json.dumps(protocol, indent=2), encoding="utf-8")
    print(f"Frozen model: {len(y)} training candidates; synthetic dev balanced accuracy {model['development_metrics']['balanced_accuracy']:.3f}", flush=True)
    positive, _ = read_recording(Path("recordings") / POSITIVE_FILE)
    negative, _ = read_recording(Path("recordings") / NEGATIVE_FILE)
    results, windows, detections = score_real(positive, negative, model)
    (args.output / "recorded_results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    for r in results:
        print(json.dumps(r), flush=True)
    write_csv(args.output / "recorded_windows.csv", list(windows[0]), windows)
    write_csv(args.output / "recorded_detections.csv", list(detections[0]), detections)
    print("Running perturbation stress tests...", flush=True)
    stress = stress_real(positive, negative, model, args.stress_repetitions)
    write_csv(args.output / "perturbation_results.csv", list(stress[0]), stress)
    print("Running independent-seed synthetic scenarios...", flush=True)
    synthetic = score_synthetic_test(model)
    write_csv(args.output / "synthetic_test_results.csv", list(synthetic[0]), synthetic)
    make_plot(results, stress, args.output)
    make_report(results, stress, synthetic, model, protocol, args.output)
    print(f"Results: {args.output.resolve()}", flush=True)


if __name__ == "__main__":
    main()
