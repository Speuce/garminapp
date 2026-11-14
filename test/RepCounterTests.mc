// ABOUTME: Simulator tests for the adaptive XYZ counter, including full labelled recordings.
// ABOUTME: Run with make test, or build.ps1 -Test -Device instinct2 / fenix7pro.
import Toybox.Lang;
import Toybox.Test;

// Helpers for feeding samples to a RepCounter.
(:test)
class Samples {

    // Returns how many reps the samples completed.
    static function feed(counter as RepCounter, samples as Array<Number>) as Number {
        var completed = 0;
        for (var i = 0; i < samples.size(); i += 3) {
            completed += counter.add(samples[i], samples[i + 1], samples[i + 2]);
        }
        return completed;
    }

    static function recording(counter as RepCounter, normal as Boolean) as Number {
        var completed = 0;
        for (var block = 0; block < 5; block++) {
            completed += feed(counter, normal ? RecordedSamples.normal(block) : RecordedSamples.negative(block));
        }
        return completed;
    }

    static function rest(counter as RepCounter, times as Number, gain as Float) as Void {
        for (var i = 0; i < times; i++) {
            counter.add((850 * gain).toNumber(), (200 * gain).toNumber(), (-250 * gain).toNumber());
        }
    }

    static function cycle(counter as RepCounter, length as Number, gain as Float) as Number {
        var completed = 0;
        for (var i = 0; i < length; i++) {
            var at = ((i * 32) / length).toNumber() * 3;
            completed += counter.add((WEAK_CYCLE_XYZ[at] * gain).toNumber(),
                (WEAK_CYCLE_XYZ[at + 1] * gain).toNumber(), (WEAK_CYCLE_XYZ[at + 2] * gain).toNumber());
        }
        return completed;
    }
}

(:test)
function freshCounterHasNoReps(logger as Logger) as Boolean {
    Test.assertEqual(new RepCounter().count(), 0);
    return true;
}

(:test)
function standingStillCountsNothing(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.rest(counter, 200, 1.0);
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function singleSwingDoesNotConfirmARun(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.rest(counter, 25, 1.0);
    Samples.cycle(counter, 32, 1.0);
    Samples.rest(counter, 100, 1.0);
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function yOnlySwingsAreNotReps(logger as Logger) as Boolean {
    var counter = new RepCounter();
    for (var i = 0; i < 20; i++) {
        for (var j = 0; j < 12; j++) { counter.add(850, 2500, -250); }
        for (var j = 0; j < 12; j++) { counter.add(850, -1000, -250); }
    }
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function recordedSetOfTwentyNormalJacksCountsTwenty(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Test.assertEqual(Samples.recording(counter, true), 20);
    Test.assertEqual(counter.count(), 20);
    return true;
}

(:test)
function recordedWatchChecksAndMarchingCountZero(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Test.assertEqual(Samples.recording(counter, false), 0);
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function threeCyclesCreditTheFirstThreeTogether(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.rest(counter, 25, 1.0);
    Test.assertEqual(Samples.cycle(counter, 32, 1.0), 0);
    Test.assertEqual(Samples.cycle(counter, 32, 1.0), 0);
    Test.assertEqual(Samples.cycle(counter, 32, 1.0), 3);
    Test.assertEqual(counter.count(), 3);
    Test.assertEqual(Samples.cycle(counter, 32, 1.0), 1);
    Test.assertEqual(counter.count(), 4);
    return true;
}

(:test)
function weakReturnsAndChangingCadenceCountEight(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.rest(counter, 25, 1.0);
    var lengths = [24, 27, 30, 33, 36, 40, 44, 48] as Array<Number>;
    for (var i = 0; i < lengths.size(); i++) {
        Samples.cycle(counter, lengths[i], 1.0);
    }
    Samples.rest(counter, 25, 1.0);
    Test.assertEqual(counter.count(), 8);
    return true;
}

(:test)
function stationaryCalibrationToleratesGainChanges(logger as Logger) as Boolean {
    var gains = [0.8, 1.0, 1.2] as Array<Float>;
    for (var i = 0; i < gains.size(); i++) {
        var counter = new RepCounter();
        Samples.rest(counter, 25, gains[i]);
        for (var j = 0; j < 8; j++) { Samples.cycle(counter, 32, gains[i]); }
        Samples.rest(counter, 25, gains[i]);
        Test.assertEqual(counter.count(), 8);
    }
    return true;
}

(:test)
function pauseClearsUnconfirmedCycles(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.rest(counter, 25, 1.0);
    Samples.cycle(counter, 32, 1.0);
    Samples.cycle(counter, 32, 1.0);
    Samples.rest(counter, 100, 1.0);
    Samples.cycle(counter, 32, 1.0);
    Samples.rest(counter, 25, 1.0);
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function timeoutRecoversForNextRun(logger as Logger) as Boolean {
    var counter = new RepCounter();
    for (var i = 0; i < 500; i++) { counter.add(500, 2000, 500); }
    Test.assertEqual(counter.count(), 0);
    Samples.rest(counter, 25, 1.0);
    for (var i = 0; i < 8; i++) { Samples.cycle(counter, 32, 1.0); }
    Samples.rest(counter, 25, 1.0);
    Test.assertEqual(counter.count(), 8);
    return true;
}

(:test)
function recordedCountsMatchReferenceAtEverySample(logger as Logger) as Boolean {
    var expected = [230, 3, 268, 1, 306, 1, 341, 1, 376, 1, 413, 1, 446, 1, 483, 1,
        516, 1, 549, 1, 583, 1, 617, 1, 654, 1, 692, 1, 729, 1, 765, 1, 802, 1, 842, 1] as Array<Number>;
    var counter = new RepCounter();
    var next = 0;
    var sample = 0;
    for (var block = 0; block < 5; block++) {
        var xyz = RecordedSamples.normal(block);
        for (var i = 0; i < xyz.size(); i += 3) {
            var credited = counter.add(xyz[i], xyz[i + 1], xyz[i + 2]);
            var reference = 0;
            if (next < expected.size() && sample == expected[next]) {
                reference = expected[next + 1];
                next += 2;
            }
            Test.assertEqual(credited, reference);
            sample++;
        }
    }
    Test.assertEqual(next, expected.size());
    return true;
}
