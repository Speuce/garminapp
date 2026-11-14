import Toybox.Lang;

// Owns one ringing session. Detection is identical to the validated counter;
// only an active session can credit reps or complete the alarm.
class AlarmChallenge {
    const TARGET = 20;
    private var _counter as RepCounter = new RepCounter();
    private var _active as Boolean = false;

    function initialize() {
    }

    function start() as Void {
        _counter = new RepCounter();
        _active = true;
    }

    function stop() as Void {
        _active = false;
    }

    function count() as Number {
        return _counter.count();
    }

    function target() as Number { return TARGET; }

    // True exactly once, at the sample that reaches the target. Samples arriving
    // after completion/onHide are ignored, including the rest of the same batch.
    function add(x as Number, y as Number, z as Number) as Boolean {
        if (!_active) { return false; }
        _counter.add(x, y, z);
        if (_counter.count() >= TARGET) {
            _active = false;
            return true;
        }
        return false;
    }
}
