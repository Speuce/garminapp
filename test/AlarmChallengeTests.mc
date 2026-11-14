import Toybox.Lang;
import Toybox.Test;

(:test)
class ChallengeSamples {
    static function recording(challenge as AlarmChallenge, normal as Boolean) as Number {
        var completed = 0;
        for (var block = 0; block < 5; block++) {
            var xyz = normal ? RecordedSamples.normal(block) : RecordedSamples.negative(block);
            for (var i = 0; i < xyz.size(); i += 3) {
                if (challenge.add(xyz[i], xyz[i + 1], xyz[i + 2])) { completed++; }
            }
        }
        return completed;
    }
}

(:test)
function alarmCompletesOnlyOnTwentiethRecordedJack(logger as Logger) as Boolean {
    var challenge = new AlarmChallenge();
    challenge.start();
    var sample = 0;
    var completions = 0;
    for (var block = 0; block < 5; block++) {
        var xyz = RecordedSamples.normal(block);
        for (var i = 0; i < xyz.size(); i += 3) {
            var completed = challenge.add(xyz[i], xyz[i + 1], xyz[i + 2]);
            Test.assertEqual(completed, sample == 842);
            if (sample < 842) { Test.assert(challenge.count() < 20); }
            if (completed) { completions++; }
            sample++;
        }
    }
    Test.assertEqual(completions, 1);
    Test.assertEqual(challenge.count(), 20);
    Test.assertEqual(ChallengeSamples.recording(challenge, true), 0);
    Test.assertEqual(challenge.count(), 20);
    return true;
}

(:test)
function watchChecksAndMarchingCannotDismissAlarm(logger as Logger) as Boolean {
    var challenge = new AlarmChallenge();
    challenge.start();
    Test.assertEqual(ChallengeSamples.recording(challenge, false), 0);
    Test.assertEqual(challenge.count(), 0);
    return true;
}

(:test)
function stoppedAlarmIgnoresLateSensorSamples(logger as Logger) as Boolean {
    var challenge = new AlarmChallenge();
    Test.assertEqual(ChallengeSamples.recording(challenge, true), 0);
    Test.assertEqual(challenge.count(), 0);
    challenge.start();
    var xyz = RecordedSamples.normal(0);
    for (var i = 0; i < xyz.size(); i += 3) {
        challenge.add(xyz[i], xyz[i + 1], xyz[i + 2]);
    }
    Test.assertEqual(challenge.count(), 3);
    challenge.stop();
    Test.assertEqual(ChallengeSamples.recording(challenge, true), 0);
    Test.assertEqual(challenge.count(), 3);
    return true;
}

(:test)
function nextAlarmStartsWithFreshDetection(logger as Logger) as Boolean {
    var challenge = new AlarmChallenge();
    challenge.start();
    Test.assertEqual(ChallengeSamples.recording(challenge, true), 1);
    challenge.start();
    Test.assertEqual(challenge.count(), 0);
    Test.assertEqual(ChallengeSamples.recording(challenge, false), 0);
    Test.assertEqual(challenge.count(), 0);
    challenge.start();
    Test.assertEqual(ChallengeSamples.recording(challenge, true), 1);
    return true;
}
