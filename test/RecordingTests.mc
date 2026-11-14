// ABOUTME: Unit tests for Recording, which turns accelerometer batches and markers into CSV log lines.
// ABOUTME: Run with `make test` while the Connect IQ simulator is open.
import Toybox.Lang;
import Toybox.Test;

(:test)
function freshRecordingIsNotRecording(logger as Logger) as Boolean {
    var recording = new Recording(25);
    Test.assert(!recording.isRecording());
    Test.assertEqual(recording.markerCount(), 0);
    return true;
}

(:test)
function startingWritesAHeaderWithTheSampleRate(logger as Logger) as Boolean {
    var recording = new Recording(25);
    Test.assertEqual(recording.start(), "start,25");
    Test.assert(recording.isRecording());
    return true;
}

(:test)
function samplesAreNumberedAcrossBatches(logger as Logger) as Boolean {
    var recording = new Recording(25);
    recording.start();
    var first = recording.samples([10, 11], [-20, -21], [980, 981]);
    var second = recording.samples([12], [-22], [982]);
    Test.assertEqual(first.size(), 2);
    Test.assertEqual(first[0], "s,0,10,-20,980");
    Test.assertEqual(first[1], "s,1,11,-21,981");
    Test.assertEqual(second[0], "s,2,12,-22,982");
    Test.assertEqual(recording.sampleCount(), 3);
    return true;
}

(:test)
function markersRecordTheCurrentSampleAndAreCounted(logger as Logger) as Boolean {
    var recording = new Recording(25);
    recording.start();
    recording.samples([1, 2, 3], [4, 5, 6], [7, 8, 9]);
    Test.assertEqual(recording.marker(), "mark,3,1");
    Test.assertEqual(recording.marker(), "mark,3,2");
    Test.assertEqual(recording.markerCount(), 2);
    return true;
}

(:test)
function stoppingWritesTheSampleTotal(logger as Logger) as Boolean {
    var recording = new Recording(25);
    recording.start();
    recording.samples([1, 2], [3, 4], [5, 6]);
    Test.assertEqual(recording.stop(), "stop,2");
    Test.assert(!recording.isRecording());
    return true;
}

(:test)
function restartingBeginsAFreshSession(logger as Logger) as Boolean {
    var recording = new Recording(25);
    recording.start();
    recording.samples([1], [2], [3]);
    recording.marker();
    recording.stop();
    recording.start();
    Test.assertEqual(recording.markerCount(), 0);
    Test.assertEqual(recording.samples([4], [5], [6])[0], "s,0,4,5,6");
    return true;
}
