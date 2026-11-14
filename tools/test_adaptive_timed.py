"""Streaming, recovery and weak-return regression tests for the adaptive counter."""

import unittest
import numpy as np

from adaptive_timed import AdaptiveCounter, detect_adaptive
from validate_detectors import detect, pulse


def weak_return_sequence(lengths):
    """Full XYZ sweeps whose Y return never reaches the old -400 mg gate."""
    base = np.array([850, 200, -250])
    chunks = [np.tile(base, (25, 1))]
    for n in lengths:
        p = np.arange(n) / n
        y = 2500 * (pulse(p, .23, .12) + .85 * pulse(p, .55, .13)) - 400 * pulse(p, .83, .065)
        x = 800 * np.sin(2 * np.pi * p + .5)
        z = 900 * np.sin(2 * np.pi * p - .7)
        envelope = np.minimum(1, np.minimum(p, 1 - p) / .08)
        chunks.append(base + np.column_stack([x, y, z]) * envelope[:, None])
    chunks.append(np.tile(base, (25, 1)))
    return np.vstack(chunks)


class AdaptiveChecks(unittest.TestCase):
    def test_recovers_reps_that_never_reach_negative_threshold(self):
        xyz = weak_return_sequence([32] * 8)
        self.assertGreater(xyz[:, 1].min(), -400)
        self.assertEqual(len(detect(xyz, "baseline")), 0)
        self.assertEqual(len(detect_adaptive(xyz)), 8)

    def test_cadence_adapts_when_cycles_slow_down(self):
        counter = AdaptiveCounter()
        found = []
        for sample in weak_return_sequence([24, 27, 30, 33, 36, 40, 44, 48]):
            ds, _ = counter.add(sample)
            found.extend(ds)
        self.assertEqual(len(found), 8)
        self.assertGreater(counter.period, 34)

    def test_startup_gravity_calibration_handles_gain(self):
        xyz = weak_return_sequence([32] * 8)
        for gain in (.8, 1.0, 1.2):
            self.assertEqual(len(detect_adaptive(xyz * gain)), 8)

    def test_isolated_motion_does_not_confirm_a_run(self):
        self.assertEqual(detect_adaptive(weak_return_sequence([32])), [])

    def test_pause_clears_unconfirmed_repetitions(self):
        xyz = weak_return_sequence([32, 32])
        xyz = np.vstack([xyz, np.tile([850, 200, -250], (100, 1)), weak_return_sequence([32])])
        self.assertEqual(detect_adaptive(xyz), [])

    def test_streaming_output_is_causal_and_has_no_duplicates(self):
        xyz = weak_return_sequence([32] * 8)
        all_ds = detect_adaptive(xyz)
        self.assertEqual(len(all_ds), 8)
        self.assertEqual(len({d.sample for d in all_ds}), 8)
        for end in range(1, len(xyz), 11):
            self.assertEqual(detect_adaptive(xyz[:end]), [d for d in all_ds if d.confirmed_at < end])
        self.assertTrue(all(d.sample <= d.confirmed_at for d in all_ds))

    def test_timeout_recovers_and_memory_is_bounded(self):
        counter = AdaptiveCounter()
        for sample in np.tile([500, 2000, 500], (500, 1)):
            ds, _ = counter.add(sample)
            self.assertFalse(ds)
        found = []
        for sample in weak_return_sequence([32] * 8):
            ds, _ = counter.add(sample)
            found.extend(ds)
        self.assertEqual(len(found), 8)
        self.assertLessEqual(len(counter.pending), 3)
        self.assertLessEqual(len(counter.calibration_norms), 20)


if __name__ == "__main__":
    unittest.main()
