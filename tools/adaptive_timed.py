"""Causal, bounded-memory candidate extraction for an adaptive XYZ counter.

Acceleration is in milli-g. Candidate completion is relative to the current
peak instead of requiring the wrist to cross an absolute negative threshold.
"""

from dataclasses import dataclass, asdict
import numpy as np


@dataclass(frozen=True)
class AdaptiveConfig:
    calibration_samples: int = 20
    calibration_max_std_g: float = .08
    smoothing: float = .3
    arm_mg: float = 650
    floor_mg: float = 100
    return_fraction: float = .10
    minimum_drop_mg: float = 650
    startup_timeout_samples: int = 65
    minimum_duration_samples: int = 4
    minimum_x_span_g: float = .35
    minimum_z_span_g: float = .45
    minimum_mean_magnitude_g: float = 1.2
    quality_threshold: float = 2.3
    minimum_mean_peak_ratio: float = .72
    strong_quality_threshold: float = 2.8
    continuation_quality_threshold: float = 2.3
    continuation_quality_fraction: float = .86
    strong_z_span_g: float = .8
    minimum_gap_samples: int = 12
    maximum_gap_samples: int = 70
    confirmation_cycles: int = 3
    cadence_weight: float = .25


DEFAULT_CONFIG = AdaptiveConfig()


@dataclass
class AdaptiveDetection:
    sample: int
    confirmed_at: int
    score: float


def config_dict(config=DEFAULT_CONFIG):
    return asdict(config)


class AdaptiveCounter:
    def __init__(self, config=DEFAULT_CONFIG):
        self.config = config
        self.filtered = None
        self.index = -1
        self.start = None
        self.peak = None
        self.minimum = None
        self.maximum = None
        self.magnitude_sum = 0.0
        self.y_sum = 0.0
        self.length = 0
        self.blocked = False
        self.pending = []
        self.active = False
        self.period = None
        self.calibration_norms = []
        self.gravity_scale = 1.0

    def _clear_candidate(self):
        self.start = None
        self.length = 0
        self.magnitude_sum = 0.0
        self.y_sum = 0.0

    def _accept(self, event):
        c = self.config
        end = event["end"]
        if self.pending:
            gap = end - self.pending[-1][0]
            lower = c.minimum_gap_samples if self.period is None else max(c.minimum_gap_samples, .45 * self.period)
            upper = c.maximum_gap_samples if self.period is None else min(c.maximum_gap_samples, 1.9 * self.period)
            if not lower <= gap <= upper:
                self.pending, self.active, self.period = [], False, None
            else:
                self.period = gap if self.period is None else (1 - c.cadence_weight) * self.period + c.cadence_weight * gap
        self.pending.append((end, event["quality"]))
        self.pending = self.pending[-c.confirmation_cycles:]
        if len(self.pending) < c.confirmation_cycles:
            return []
        if self.active:
            return [AdaptiveDetection(end, end, event["quality"])]
        self.active = True
        return [AdaptiveDetection(i, end, score) for i, score in self.pending]

    def add(self, xyz):
        """Return (newly confirmed reps, completed candidate or None)."""
        c = self.config
        self.index += 1
        sample = np.asarray(xyz, dtype=float)
        # Only calibrate during the startup window, and only if it looks still.
        # Use the resting gravity magnitude to tolerate modest sensor gain
        # differences. If started in motion, retain the nominal milli-g scale.
        if self.index < c.calibration_samples:
            self.calibration_norms.append(np.linalg.norm(sample) / 1000)
            if self.index + 1 == c.calibration_samples:
                average = float(np.mean(self.calibration_norms))
                if .6 <= average <= 1.4 and np.std(self.calibration_norms) < c.calibration_max_std_g:
                    self.gravity_scale = average
        sample = sample / self.gravity_scale
        self.filtered = sample.copy() if self.filtered is None else self.filtered + c.smoothing * (sample - self.filtered)
        y = self.filtered[1]
        if self.pending and self.index - self.pending[-1][0] > c.maximum_gap_samples:
            self.pending, self.active, self.period = [], False, None
        if self.blocked:
            if y < c.arm_mg:
                self.blocked = False
            return [], None
        if self.start is None:
            if y <= c.arm_mg:
                return [], None
            self.start = self.index
            self.peak = y
            self.minimum = self.filtered.copy()
            self.maximum = self.filtered.copy()
        self.peak = max(self.peak, y)
        self.minimum = np.minimum(self.minimum, self.filtered)
        self.maximum = np.maximum(self.maximum, self.filtered)
        self.magnitude_sum += np.linalg.norm(sample) / 1000
        self.y_sum += max(0, y) / 1000
        self.length += 1
        age = self.index - self.start
        timeout = c.startup_timeout_samples if self.period is None else min(c.startup_timeout_samples, max(30, 1.4 * self.period))
        if age > timeout:
            self._clear_candidate()
            self.blocked = y >= c.arm_mg
            return [], None
        return_level = c.floor_mg + c.return_fraction * (self.peak - c.floor_mg)
        if y > return_level or self.peak - y < c.minimum_drop_mg:
            return [], None
        spans = (self.maximum - self.minimum) / 1000
        mean_magnitude = self.magnitude_sum / self.length
        event = {"start": self.start, "end": self.index, "duration_samples": age,
                 "peak_y_g": self.peak / 1000, "x_span_g": spans[0], "z_span_g": spans[2],
                 "mean_magnitude_g": mean_magnitude,
                 "y_mean_peak_ratio": self.y_sum / self.length / (self.peak / 1000),
                 "quality": mean_magnitude + .5 * spans[2] + .25 * spans[0]}
        self._clear_candidate()
        self.blocked = True
        strong_threshold = c.strong_quality_threshold
        if self.active or len(self.pending) >= 2:
            strong_threshold = max(c.continuation_quality_threshold,
                                   c.continuation_quality_fraction * np.median([score for _, score in self.pending]))
        valid = (age >= c.minimum_duration_samples and spans[0] >= c.minimum_x_span_g
                 and spans[2] >= c.minimum_z_span_g and mean_magnitude >= c.minimum_mean_magnitude_g
                 and event["quality"] >= c.quality_threshold
                 and (event["y_mean_peak_ratio"] >= c.minimum_mean_peak_ratio
                      or (event["quality"] >= strong_threshold and spans[2] >= c.strong_z_span_g)))
        event["accepted"] = bool(valid)
        return self._accept(event) if valid else [], event


def detect_adaptive(xyz, config=DEFAULT_CONFIG, include_candidates=False):
    counter = AdaptiveCounter(config)
    detections, events = [], []
    for sample in xyz:
        new, event = counter.add(sample)
        detections.extend(new)
        if include_candidates and event is not None:
            events.append(event)
    return (detections, events) if include_candidates else detections
