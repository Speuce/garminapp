// ABOUTME: Adaptive jumping-jack counter for calibrated XYZ samples in milli-g at ~25 Hz.
// ABOUTME: Uses peak-relative returns, cadence, PCA-only gating and three-cycle confirmation.
import Toybox.Lang;
import Toybox.Math;

class RepCounter {
    private const CALIBRATION_SAMPLES = 20;
    private const SMOOTHING = 0.3;
    private const ARM = 650.0;
    private const RETURN_FLOOR = 100.0;
    private const RETURN_FRACTION = 0.10;
    private const MIN_DROP = 650.0;
    private const MAX_CANDIDATE_SAMPLES = 65.0;
    private const MAX_GAP = 70;

    private var _count as Number = 0;
    private var _index as Number = -1;
    private var _calibrationMean as Float = 0.0;
    private var _calibrationM2 as Float = 0.0;
    private var _gravityScale as Float = 1.0;
    private var _initialized as Boolean = false;
    private var _x as Float = 0.0;
    private var _y as Float = 0.0;
    private var _z as Float = 0.0;
    private var _start as Number = -1;
    private var _peak as Float = 0.0;
    private var _minX as Float = 0.0;
    private var _maxX as Float = 0.0;
    private var _minZ as Float = 0.0;
    private var _maxZ as Float = 0.0;
    private var _magnitudeSum as Float = 0.0;
    private var _ySum as Float = 0.0;
    private var _length as Number = 0;
    private var _blocked as Boolean = false;
    private var _pending as Number = 0;
    private var _lastRep as Number = -1;
    private var _active as Boolean = false;
    private var _period as Float = 0.0;
    private var _quality0 as Float = 0.0;
    private var _quality1 as Float = 0.0;
    private var _quality2 as Float = 0.0;
    private var _motionPca as PcaMotionGate = new PcaMotionGate();

    function initialize() {
    }

    function count() as Number {
        return _count;
    }

    // Returns the number newly credited: 3 when a run is first confirmed,
    // then 1 per accepted cycle. Keep this instance across sensor batches.
    function add(x as Number, y as Number, z as Number) as Number {
        _index++;
        _motionPca.add(x, y, z);
        var rawX = x.toFloat();
        var rawY = y.toFloat();
        var rawZ = z.toFloat();
        // Convert before squaring to avoid integer overflow on large samples.
        var magnitude = Math.sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ).toFloat() / 1000.0;
        if (_index < CALIBRATION_SAMPLES) {
            // Welford population variance, equivalent to the reference's std().
            var delta = magnitude - _calibrationMean;
            _calibrationMean += delta / (_index + 1);
            _calibrationM2 += delta * (magnitude - _calibrationMean);
            if (_index + 1 == CALIBRATION_SAMPLES &&
                _calibrationMean >= 0.6 && _calibrationMean <= 1.4 &&
                _calibrationM2 / CALIBRATION_SAMPLES < 0.0064) {
                _gravityScale = _calibrationMean;
            }
        }
        rawX /= _gravityScale;
        rawY /= _gravityScale;
        rawZ /= _gravityScale;
        magnitude /= _gravityScale;
        if (!_initialized) {
            _x = rawX;
            _y = rawY;
            _z = rawZ;
            _initialized = true;
        } else {
            _x += SMOOTHING * (rawX - _x);
            _y += SMOOTHING * (rawY - _y);
            _z += SMOOTHING * (rawZ - _z);
        }
        if (_pending > 0 && _index - _lastRep > MAX_GAP) {
            clearRun();
        }
        if (_blocked) {
            if (_y < ARM) {
                _blocked = false;
            }
            return 0;
        }
        if (_start < 0) {
            if (_y <= ARM) {
                return 0;
            }
            _start = _index;
            _peak = _y;
            _minX = _x;
            _maxX = _x;
            _minZ = _z;
            _maxZ = _z;
        }
        _peak = maximum(_peak, _y);
        _minX = minimum(_minX, _x);
        _maxX = maximum(_maxX, _x);
        _minZ = minimum(_minZ, _z);
        _maxZ = maximum(_maxZ, _z);
        _magnitudeSum += magnitude;
        _ySum += maximum(0.0, _y) / 1000.0;
        _length++;
        var age = _index - _start;
        var timeout = _period == 0.0 ? MAX_CANDIDATE_SAMPLES :
            minimum(MAX_CANDIDATE_SAMPLES, maximum(30.0, 1.4 * _period));
        if (age > timeout) {
            clearCandidate();
            _blocked = _y >= ARM;
            return 0;
        }
        var returnLevel = RETURN_FLOOR + RETURN_FRACTION * (_peak - RETURN_FLOOR);
        if (_y > returnLevel || _peak - _y < MIN_DROP) {
            return 0;
        }
        var xSpan = (_maxX - _minX) / 1000.0;
        var zSpan = (_maxZ - _minZ) / 1000.0;
        var meanMagnitude = _magnitudeSum / _length;
        var meanPeakRatio = _ySum / _length / (_peak / 1000.0);
        var quality = meanMagnitude + 0.5 * zSpan + 0.25 * xSpan;
        clearCandidate();
        _blocked = true;
        var strongThreshold = 2.8;
        if (_active || _pending >= 2) {
            strongThreshold = maximum(2.3, 0.86 * medianQuality());
        }
        if (age < 4 || xSpan < 0.35 || zSpan < 0.45 || meanMagnitude < 1.2 ||
            quality < 2.3 || (meanPeakRatio < 0.72 && (quality < strongThreshold || zSpan < 0.8))) {
            return 0;
        }
        // Match the Python PCA-only prototype: current candidate + 8 earlier
        // samples, gated before confirmation. A rejected cycle clears the run.
        if (!_motionPca.allows(age + 9)) {
            clearRun();
            return 0;
        }
        return accept(quality);
    }

    private function accept(quality as Float) as Number {
        if (_pending > 0) {
            var gap = _index - _lastRep;
            var lower = _period == 0.0 ? 12.0 : maximum(12.0, 0.45 * _period);
            var upper = _period == 0.0 ? 70.0 : minimum(70.0, 1.9 * _period);
            if (gap < lower || gap > upper) {
                clearRun();
            } else {
                _period = _period == 0.0 ? gap.toFloat() : 0.75 * _period + 0.25 * gap;
            }
        }
        if (_pending == 0) {
            _quality0 = quality;
        } else if (_pending == 1) {
            _quality1 = quality;
        } else if (_pending == 2) {
            _quality2 = quality;
        } else {
            _quality0 = _quality1;
            _quality1 = _quality2;
            _quality2 = quality;
        }
        if (_pending < 3) {
            _pending++;
        }
        _lastRep = _index;
        if (_pending < 3) {
            return 0;
        }
        var credited = _active ? 1 : 3;
        _active = true;
        _count += credited;
        return credited;
    }

    private function clearCandidate() as Void {
        _start = -1;
        _length = 0;
        _magnitudeSum = 0.0;
        _ySum = 0.0;
    }

    private function clearRun() as Void {
        _pending = 0;
        _active = false;
        _period = 0.0;
    }

    private function medianQuality() as Float {
        if (_pending == 2) {
            return (_quality0 + _quality1) / 2.0;
        }
        return maximum(minimum(_quality0, _quality1), minimum(maximum(_quality0, _quality1), _quality2));
    }

    private function minimum(a as Float, b as Float) as Float {
        return a < b ? a : b;
    }

    private function maximum(a as Float, b as Float) as Float {
        return a > b ? a : b;
    }
}
