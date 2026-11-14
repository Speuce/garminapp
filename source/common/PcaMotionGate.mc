import Toybox.Lang;

// PCA-only filter from the local validation: the smallest principal component
// must explain at least 0.6% of XYZ variance. This rejects nearly planar motion;
// it is not proof of takeoff or landing. No impact/FFT filter is applied.
class PcaMotionGate {
    private const CAPACITY = 74; // 66 candidate samples plus eight preceding it.
    private const MIN_FRACTION = 0.006;
    private var _samples as Array<Number> = new [222] as Array<Number>;
    private var _next as Number = 0;
    private var _available as Number = 0;

    function initialize() {}

    function add(x as Number, y as Number, z as Number) as Void {
        var at = _next * 3;
        _samples[at] = x;
        _samples[at + 1] = y;
        _samples[at + 2] = z;
        _next = (_next + 1) % CAPACITY;
        if (_available < CAPACITY) { _available++; }
    }

    function allows(length as Number) as Boolean {
        var n = length < _available ? length : _available;
        if (n < 4) { return false; }
        var first = (_next - n + CAPACITY) % CAPACITY;
        var mx = 0.0;
        var my = 0.0;
        var mz = 0.0;
        for (var i = 0; i < n; i++) {
            var at = ((first + i) % CAPACITY) * 3;
            mx += _samples[at].toFloat() / 1000.0;
            my += _samples[at + 1].toFloat() / 1000.0;
            mz += _samples[at + 2].toFloat() / 1000.0;
        }
        mx /= n;
        my /= n;
        mz /= n;
        var xx = 0.0;
        var yy = 0.0;
        var zz = 0.0;
        var xy = 0.0;
        var xz = 0.0;
        var yz = 0.0;
        for (var i = 0; i < n; i++) {
            var at = ((first + i) % CAPACITY) * 3;
            var x = _samples[at].toFloat() / 1000.0 - mx;
            var y = _samples[at + 1].toFloat() / 1000.0 - my;
            var z = _samples[at + 2].toFloat() / 1000.0 - mz;
            xx += x * x;
            yy += y * y;
            zz += z * z;
            xy += x * y;
            xz += x * z;
            yz += y * z;
        }
        var trace = xx + yy + zz;
        if (trace <= 0.00000001) { return false; }

        // lambda_min(C) / trace(C) >= t exactly when C/trace(C) - t*I
        // is positive semidefinite. Check ALL principal minors of this 3x3
        // symmetric matrix, avoiding an eigensolver and per-sample allocation.
        // The common covariance divisor and gravity calibration cancel out.
        var a = xx / trace - MIN_FRACTION;
        var d = yy / trace - MIN_FRACTION;
        var f = zz / trace - MIN_FRACTION;
        var b = xy / trace;
        var c = xz / trace;
        var e = yz / trace;
        if (a < 0.0 || d < 0.0 || f < 0.0) { return false; }
        if (a * d - b * b < 0.0 || a * f - c * c < 0.0 || d * f - e * e < 0.0) {
            return false;
        }
        return a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d) >= 0.0;
    }
}
