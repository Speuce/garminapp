import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Temporary diagnostics on the experimental branch. Garmin writes println to
// GARMIN/APPS/LOGS/JumpStart.TXT only when that file has been created over USB.
// Limit raw motion to the first 1,500 samples (~60 s); never log heart rate.
class MotionTrace {
    private var _remaining as Number = 0;
    private var _index as Number = 0;
    private var _active as Boolean = false;

    function initialize() {}

    function start(preview as Boolean) as Void {
        _remaining = 1500;
        _index = 0;
        _active = true;
        System.println("JJTRACE,BEGIN,impact-v2-pc60," + Time.now().value() + "," +
            System.getTimer() + "," + (preview ? "test" : "scheduled"));
    }

    function samples(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Void {
        if (!_active || _remaining <= 0) { return; }
        var n = x.size();
        if (n > y.size()) { n = y.size(); }
        if (n > z.size()) { n = z.size(); }
        if (n > _remaining) { n = _remaining; }
        // At most 25 triples per line, even if firmware batches more samples.
        for (var first = 0; first < n; first += 25) {
            var end = first + 25;
            if (end > n) { end = n; }
            var line = "JJTRACE,ACCEL," + System.getTimer() + "," + (_index + first);
            for (var i = first; i < end; i++) {
                line += "," + x[i] + "," + y[i] + "," + z[i];
            }
            System.println(line);
        }
        _index += n;
        _remaining -= n;
    }

    function vibration() as Void {
        if (_active && _remaining > 0) {
            System.println("JJTRACE,VIBRATION," + System.getTimer() + ",400,150,400");
        }
    }

    function stop() as Void {
        if (!_active) { return; }
        System.println("JJTRACE,END," + System.getTimer() + "," + _index);
        _active = false;
    }
}
