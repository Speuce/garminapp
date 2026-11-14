import Toybox.Lang;
import Toybox.Math;

// PCA + impact prototype from the local validation. These are wrist-motion
// checks, not proof of takeoff or landing. All scratch storage is bounded.
class PcaMotionGate {
    private const CAPACITY = 74; // 66 candidate samples plus eight preceding it.
    private const MIN_FRACTION = 0.006;
    private const MIN_RESIDUAL_CHANGE_SQUARED = 0.09; // (0.3 g/sample)^2
    private const MIN_HIGH_FREQUENCY_FRACTION = 0.08;
    private var _samples as Array<Number> = new [222] as Array<Number>;
    private var _window as Array<Float> = new [222] as Array<Float>;
    private var _matrix as Array<Float> = new [9] as Array<Float>;
    private var _basis as Array<Float> = new [9] as Array<Float>;
    private var _axisX as Float = 1.0;
    private var _axisY as Float = 0.0;
    private var _axisZ as Float = 0.0;
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

    function allows(length as Number, gravityScale as Float) as Boolean {
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
            _window[i * 3] = x;
            _window[i * 3 + 1] = y;
            _window[i * 3 + 2] = z;
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
        if (a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d) < 0.0) {
            return false;
        }
        findPrincipalAxis(xx / trace, xy / trace, xz / trace,
            yy / trace, yz / trace, zz / trace);
        return hasImpact(n, gravityScale);
    }

    // Jacobi diagonalization of the symmetric 3x3 covariance. A fixed iteration
    // limit keeps execution bounded; only the largest component's axis is used.
    private function findPrincipalAxis(xx as Float, xy as Float, xz as Float,
                                        yy as Float, yz as Float, zz as Float) as Void {
        _matrix[0] = xx; _matrix[1] = xy; _matrix[2] = xz;
        _matrix[3] = xy; _matrix[4] = yy; _matrix[5] = yz;
        _matrix[6] = xz; _matrix[7] = yz; _matrix[8] = zz;
        for (var i = 0; i < 9; i++) { _basis[i] = i % 4 == 0 ? 1.0 : 0.0; }
        for (var step = 0; step < 24; step++) {
            var p = 0;
            var q = 1;
            var largest = absolute(_matrix[1]);
            if (absolute(_matrix[2]) > largest) {
                p = 0; q = 2; largest = absolute(_matrix[2]);
            }
            if (absolute(_matrix[5]) > largest) {
                p = 1; q = 2; largest = absolute(_matrix[5]);
            }
            if (largest < 0.0000001) { break; }
            var pp = p * 3 + p;
            var qq = q * 3 + q;
            var pq = p * 3 + q;
            var off = _matrix[pq];
            var tau = (_matrix[qq] - _matrix[pp]) / (2.0 * off);
            var root = Math.sqrt(1.0 + tau * tau).toFloat();
            var t = tau >= 0.0 ? 1.0 / (tau + root) : -1.0 / (-tau + root);
            var cosine = 1.0 / Math.sqrt(1.0 + t * t).toFloat();
            var sine = t * cosine;
            _matrix[pp] -= t * off;
            _matrix[qq] += t * off;
            _matrix[pq] = 0.0;
            _matrix[q * 3 + p] = 0.0;
            for (var r = 0; r < 3; r++) {
                if (r != p && r != q) {
                    var rp = _matrix[r * 3 + p];
                    var rq = _matrix[r * 3 + q];
                    var newP = cosine * rp - sine * rq;
                    var newQ = sine * rp + cosine * rq;
                    _matrix[r * 3 + p] = newP;
                    _matrix[p * 3 + r] = newP;
                    _matrix[r * 3 + q] = newQ;
                    _matrix[q * 3 + r] = newQ;
                }
                var vp = _basis[r * 3 + p];
                var vq = _basis[r * 3 + q];
                _basis[r * 3 + p] = cosine * vp - sine * vq;
                _basis[r * 3 + q] = sine * vp + cosine * vq;
            }
        }
        var column = _matrix[4] > _matrix[0] ? 1 : 0;
        if (_matrix[8] > _matrix[column * 3 + column]) { column = 2; }
        _axisX = _basis[column];
        _axisY = _basis[3 + column];
        _axisZ = _basis[6 + column];
    }

    private function hasImpact(n as Number, gravityScale as Float) as Boolean {
        var residualChange = 0.0;
        for (var i = 1; i < n; i++) {
            var at = i * 3;
            var dx = _window[at] - _window[at - 3];
            var dy = _window[at + 1] - _window[at - 2];
            var dz = _window[at + 2] - _window[at - 1];
            var along = dx * _axisX + dy * _axisY + dz * _axisZ;
            var residual = dx * dx + dy * dy + dz * dz - along * along;
            // Subtracting nearly equal energies can round just below zero.
            if (residual > 0.0) { residualChange += residual; }
        }
        if (residualChange / (n - 1) < MIN_RESIDUAL_CHANGE_SQUARED * gravityScale * gravityScale) {
            return false;
        }

        // Same symmetric Hann window as numpy.hanning(n), after mean removal.
        for (var i = 0; i < n; i++) {
            var weight = 0.5 - 0.5 * Math.cos(2.0 * Math.PI * i / (n - 1)).toFloat();
            _window[i * 3] *= weight;
            _window[i * 3 + 1] *= weight;
            _window[i * 3 + 2] *= weight;
        }
        var fullEnergy = 0.0;
        var highEnergy = 0.0;
        // Goertzel computes exactly the DFT bins used by the Python rfft,
        // without allocating complex arrays or computing trig for each sample.
        for (var k = 1; k <= n / 2; k++) {
            if (50 * k < n) { continue; } // Frequency below 0.5 Hz at 25 Hz.
            var coefficient = 2.0 * Math.cos(2.0 * Math.PI * k / n).toFloat();
            var x1 = 0.0; var x2 = 0.0;
            var y1 = 0.0; var y2 = 0.0;
            var z1 = 0.0; var z2 = 0.0;
            for (var i = 0; i < n; i++) {
                var at = i * 3;
                var x0 = _window[at] + coefficient * x1 - x2;
                var y0 = _window[at + 1] + coefficient * y1 - y2;
                var z0 = _window[at + 2] + coefficient * z1 - z2;
                x2 = x1; x1 = x0;
                y2 = y1; y1 = y0;
                z2 = z1; z1 = z0;
            }
            var energy = x1 * x1 + x2 * x2 - coefficient * x1 * x2
                + y1 * y1 + y2 * y2 - coefficient * y1 * y2
                + z1 * z1 + z2 * z2 - coefficient * z1 * z2;
            if (energy > 0.0) {
                fullEnergy += energy;
                if (25 * k >= 3 * n && 25 * k <= 10 * n) { highEnergy += energy; }
            }
        }
        return fullEnergy > 0.0000000001 && highEnergy >= MIN_HIGH_FREQUENCY_FRACTION * fullEnergy;
    }

    private function absolute(value as Float) as Float {
        return value < 0.0 ? -value : value;
    }
}
