import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// Enable only heart rate, leaving the independent accelerometer listener alone.
class HeartRateSource {
    function initialize() {}
    function enable() as Boolean { return Sensor.enableSensorType(Sensor.SENSOR_HEARTRATE); }
    function disable() as Void { Sensor.disableSensorType(Sensor.SENSOR_HEARTRATE); }
    function read() as Number? { return Sensor.getInfo().heartRate; }
}

class HeartRateMonitor {
    private var _source as HeartRateSource;
    private var _active as Boolean = false;
    private var _enabled as Boolean = false;

    function initialize(source as HeartRateSource?) {
        _source = source == null ? new HeartRateSource() : source;
    }

    function start() as Void {
        if (_active) { return; }
        _active = true;
        // A false result need not prevent reading data already supplied by the
        // watch or simulator. Only undo an enable request that succeeded.
        try { _enabled = _source.enable(); }
        catch (e) { System.println("Heart rate unavailable: " + e.getErrorMessage()); }
    }

    function stop() as Void {
        if (!_active) { return; }
        _active = false;
        if (!_enabled) { return; }
        _enabled = false;
        try { _source.disable(); }
        catch (e) { System.println("Heart rate cleanup: " + e.getErrorMessage()); }
    }

    // Never display an old history entry as a current reading. No contact or a
    // missing sensor produces --; heart rate availability cannot block an alarm.
    function current() as Number? {
        if (!_active) { return null; }
        try {
            var value = _source.read();
            return value != null && value > 0 ? value : null;
        } catch (e) { return null; }
    }
}

module HeartRateDisplay {
    function heart(dc, x, y, radius, color) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - radius, y - radius * 0.6, radius);
        dc.fillCircle(x + radius, y - radius * 0.6, radius);
        dc.fillPolygon([[x - radius * 2, y], [x + radius * 2, y],
            [x, y + radius * 2]] as Array<Graphics.Point2D>);
    }

    function draw(dc, cx, cy, rate as Number?, font, ink, heartInk, units as Boolean) as Void {
        var value = rate == null ? "--" : rate.toString();
        var numW = dc.getTextWidthInPixels(value, font);
        var unitW = units ? dc.getTextWidthInPixels("bpm", Graphics.FONT_XTINY) + 4 : 0;
        var left = cx - (18 + numW + unitW) / 2;
        heart(dc, left + 6, cy, 3, heartInk);
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + 18, cy, font, value,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (units) {
            dc.drawText(left + 18 + numW + 4, cy, Graphics.FONT_XTINY, "bpm",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
