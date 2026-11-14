// ABOUTME: Counts jumping jacks from a stream of accelerometer Y-axis samples (milli-g, ~25 Hz).
// ABOUTME: Smooths the signal, then counts each rise above HIGH followed by a fall below LOW as one rep.
import Toybox.Lang;

class RepCounter {

    // Tuned on a recorded 20-rep set (left wrist, Instinct 2): every LOW in -750..0 and HIGH in 0..1750 counted 20.
    // These sit in the middle of that range.
    private const HIGH = 1000.0;
    private const LOW = -400.0;
    // Exponential smoothing weight for each new sample.
    private const SMOOTHING = 0.3;

    private var _smoothed as Float?;
    private var _armsUp as Boolean = false;
    private var _count as Number = 0;

    function initialize() {
    }

    function count() as Number {
        return _count;
    }

    // Returns true when this sample completes a rep.
    function add(y as Number) as Boolean {
        var previous = _smoothed;
        var smoothed = previous == null ? y.toFloat() : previous + SMOOTHING * (y - previous);
        _smoothed = smoothed;
        if (!_armsUp && smoothed > HIGH) {
            _armsUp = true;
        } else if (_armsUp && smoothed < LOW) {
            _armsUp = false;
            _count++;
            return true;
        }
        return false;
    }

}
