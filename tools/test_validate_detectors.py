"""Checks that protect the validation metrics and timed detector behavior.

Run: .venv/Scripts/python.exe -B -m unittest discover -s tools -p test_validate_detectors.py
"""

import unittest

import numpy as np

from validate_detectors import (
    ACTIVE_INTERVAL, Detection, classification_metrics, detect, fit_classifier,
    match_events, predict, synthetic_session, timed_candidates, window_rows,
)


class ValidationChecks(unittest.TestCase):
    def test_always_negative_is_not_high_balanced_accuracy(self):
        metrics = classification_metrics([True] + [False] * 99, [False] * 100)
        self.assertEqual(metrics["accuracy"], .99)
        self.assertEqual(metrics["balanced_accuracy"], .5)

    def test_duplicate_detections_cannot_inflate_recall(self):
        matches, missing, extras = match_events(
            [Detection(100, 100), Detection(101, 101)], [100, 150])
        self.assertEqual(len(matches), 1)
        self.assertEqual(len(missing), 1)
        self.assertEqual(len(extras), 1)

    def test_timed_state_expires_and_requires_low_to_rearm(self):
        # The first high is held far too long; a subsequent valid movement works.
        y = np.array([0.] * 5 + [1500.] * 80 + [-500.] * 5 + [1500.] * 10 + [-500.])
        filtered = np.column_stack([np.zeros(len(y)), y, np.zeros(len(y))])
        events = list(timed_candidates(filtered))
        self.assertEqual(sum(e is None for e in events), 1)
        self.assertEqual([e for e in events if e is not None], [(90, 100)])

    def test_window_scoring_excludes_mixed_boundaries(self):
        rows = window_rows(np.zeros((1025, 3)), [], True)
        self.assertEqual(sum(r["actual_jack_activity"] for r in rows), 14)
        self.assertEqual(sum(not r["actual_jack_activity"] for r in rows), 5)
        for row in rows:
            if row["actual_jack_activity"]:
                self.assertGreaterEqual(row["start_sample"], ACTIVE_INTERVAL[0])
                self.assertLessEqual(row["end_sample"], ACTIVE_INTERVAL[1])

    def test_confirmation_has_no_access_to_future_samples(self):
        # A deterministic, regular motion exercises actual run confirmation;
        # a random stress trace may correctly produce no accepted three-cycle run.
        phase = np.arange(35) / 35 * 2 * np.pi
        cycle = np.column_stack([1000 + 700 * np.cos(phase),
                                 200 + 2300 * np.sin(phase),
                                 800 * np.sin(phase - .7)])
        xyz = np.tile(cycle, (10, 1))
        complete = detect(xyz, "timed_xyz")
        self.assertGreater(len(complete), 0)
        for cutoff in range(25, len(xyz), 25):
            prefix = detect(xyz[:cutoff], "timed_xyz")
            expected = [d for d in complete if d.confirmed_at < cutoff]
            self.assertEqual(prefix, expected)
        self.assertTrue(all(d.sample <= d.confirmed_at for d in complete))

    def test_classifier_uses_frozen_scaling_at_prediction(self):
        rng = np.random.default_rng(8)
        x = np.vstack([rng.normal(-1, .3, (20, 8)), rng.normal(1, .3, (20, 8))])
        y = np.array([0] * 20 + [1] * 20)
        model = fit_classifier(x, y)
        before = predict(model, x[:1])[0]
        with_outlier = predict(model, np.vstack([x[:1], np.ones((1, 8)) * 100]))[0]
        self.assertEqual(before, with_outlier)
        self.assertGreater(np.mean((predict(model, x) >= .5) == y), .95)


if __name__ == "__main__":
    unittest.main()
