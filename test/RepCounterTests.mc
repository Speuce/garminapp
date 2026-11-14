// ABOUTME: Unit tests for RepCounter, which counts jumping jacks from the accelerometer Y axis.
// ABOUTME: Run with `make test` while the Connect IQ simulator is open.
import Toybox.Lang;
import Toybox.Test;

// Helpers for feeding samples to a RepCounter.
(:test)
class Samples {

    // Returns how many reps the samples completed.
    static function feed(counter as RepCounter, samples as Array<Number>) as Number {
        var completed = 0;
        for (var i = 0; i < samples.size(); i++) {
            if (counter.add(samples[i])) {
                completed++;
            }
        }
        return completed;
    }

    static function repeated(value as Number, times as Number) as Array<Number> {
        var samples = new Array<Number>[times];
        for (var i = 0; i < times; i++) {
            samples[i] = value;
        }
        return samples;
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
    Test.assertEqual(Samples.feed(counter, Samples.repeated(220, 100)), 0);
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function oneSwingUpAndBackDownCountsOneRep(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.feed(counter, Samples.repeated(0, 25));
    Samples.feed(counter, Samples.repeated(2500, 12));
    Test.assertEqual(counter.count(), 0);
    Test.assertEqual(Samples.feed(counter, Samples.repeated(-1500, 12)), 1);
    Test.assertEqual(counter.count(), 1);
    return true;
}

(:test)
function swaysBetweenThresholdsAreNotReps(logger as Logger) as Boolean {
    var counter = new RepCounter();
    for (var i = 0; i < 20; i++) {
        Samples.feed(counter, Samples.repeated(800, 12));
        Samples.feed(counter, Samples.repeated(-200, 12));
    }
    Test.assertEqual(counter.count(), 0);
    return true;
}

(:test)
function recordedSetOfTwentyNormalJacksCountsTwenty(logger as Logger) as Boolean {
    var counter = new RepCounter();
    Samples.feed(counter, SET1_NORMAL_20_REPS);
    Test.assertEqual(counter.count(), 20);
    return true;
}
