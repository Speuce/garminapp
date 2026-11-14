// ABOUTME: A raw accelerometer recording session, producing one CSV log line per sample or event.
// ABOUTME: Lines: "start,<hz>", "s,<n>,<x>,<y>,<z>" in milli-g, "mark,<n>,<k>" for the k-th marker at sample n, "stop,<n>".
import Toybox.Lang;

class Recording {

    private var _sampleRate as Number;
    private var _recording as Boolean = false;
    private var _sampleCount as Number = 0;
    private var _markerCount as Number = 0;

    function initialize(sampleRate as Number) {
        _sampleRate = sampleRate;
    }

    function isRecording() as Boolean {
        return _recording;
    }

    function markerCount() as Number {
        return _markerCount;
    }

    function start() as String {
        _recording = true;
        _sampleCount = 0;
        _markerCount = 0;
        return "start," + _sampleRate;
    }

    function samples(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Array<String> {
        var lines = new Array<String>[x.size()];
        for (var i = 0; i < x.size(); i++) {
            lines[i] = "s," + _sampleCount + "," + x[i] + "," + y[i] + "," + z[i];
            _sampleCount++;
        }
        return lines;
    }

    function marker() as String {
        _markerCount++;
        return "mark," + _sampleCount + "," + _markerCount;
    }

    function stop() as String {
        _recording = false;
        return "stop," + _sampleCount;
    }

}
