import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class RingView extends WatchUi.View {
    private var _timer as Timer.Timer?;
    private var _challenge as AlarmChallenge = new AlarmChallenge();
    private var _listening as Boolean = false;
    private var _sensorError as Boolean = false;
    private var _preview as Boolean;
    private var _receivedSamples as Boolean = false;

    function initialize(preview as Boolean) {
        View.initialize();
        _preview = preview;
    }

    function onShow() as Void {
        _challenge.start();
        _sensorError = false;
        _receivedSamples = false;
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => {:enabled => true, :sampleRate => 25}
            });
            _listening = true;
        } catch (e) {
            _challenge.stop();
            _sensorError = true;
            System.println("Alarm accelerometer unavailable: " + e.getErrorMessage());
        }
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1500, true);
        alert();
    }

    function onHide() as Void {
        _challenge.stop();
        if (_listening) {
            Sensor.unregisterSensorDataListener();
            _listening = false;
        }
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (Attention has :vibrate) {
            Attention.vibrate([] as Array<Attention.VibeProfile>);
        }
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (!_listening || accel == null) { return; }
        _receivedSamples = true;
        var previous = _challenge.count();
        for (var i = 0; i < accel.x.size(); i++) {
            if (_challenge.add(accel.x[i], accel.y[i], accel.z[i])) {
                System.println("Alarm complete: " + _challenge.count() + " jumping jacks");
                finish();
                return;
            }
        }
        if (_challenge.count() != previous) {
            System.println("Alarm jumping jacks: " + _challenge.count());
        }
        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        alert();
        WatchUi.requestUpdate();
    }

    // A preview can be cancelled without touching a scheduled alarm. A sensor
    // failure also leaves an exit, but ordinary button presses cannot dismiss.
    function cancel() as Void {
        if (_preview || _sensorError) { finish(); }
    }

    private function finish() as Void {
        onHide();
        getApp().finishRing(_preview);
    }

    private function alert() as Void {
        if (Attention has :backlight) { Attention.backlight(true); }
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 400)
            ] as Array<Attention.VibeProfile>);
        }
        if (Attention has :playTone) { Attention.playTone(Attention.TONE_ALARM); }
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        // Match the Trail theme while preserving the Instinct's cutout layout.
        var color = w >= 240;
        var fg = color ? 0xF1F5E9 : Graphics.COLOR_WHITE;
        var bg = color ? 0x10150F : Graphics.COLOR_BLACK;
        var accent = color ? 0xCCFF66 : Graphics.COLOR_WHITE;
        var align = Graphics.TEXT_JUSTIFY_CENTER |
            (color ? Graphics.TEXT_JUSTIFY_VCENTER : 0);
        dc.setColor(fg, bg);
        dc.clear();
        dc.setColor(accent, bg);
        dc.drawText(color ? w / 2 : w * 0.30, h * (color ? 0.19 : 0.10), Graphics.FONT_XTINY,
            _preview ? "TEST ALARM" : "WAKE UP", align);
        dc.drawText(w / 2, h * (color ? 0.43 : 0.38), Graphics.FONT_NUMBER_HOT,
            _challenge.count().toString() + "/" + _challenge.target().toString(),
            align);
        dc.setColor(fg, bg);
        dc.drawText(w / 2, h * 0.65, Graphics.FONT_SMALL,
            "JUMPING JACKS", align);
        var status = !_receivedSamples ? "Stand still briefly" : "Keep going to stop";
        if (_sensorError) { status = "Sensor unavailable"; }
        dc.drawText(w / 2, h * 0.76, Graphics.FONT_XTINY, status, align);
        if (color) {
            dc.setColor(0x26331A, bg);
            dc.fillRoundedRectangle(w * 0.2, h * 0.83, w * 0.6, 5, 2);
            dc.setColor(accent, bg);
            dc.fillRoundedRectangle(w * 0.2, h * 0.83, w * 0.6 * _challenge.count() / _challenge.target(), 5, 2);
        }
        if (_preview || _sensorError) {
            dc.drawText(w / 2, h * (color ? 0.90 : 0.86), Graphics.FONT_XTINY,
                "BACK = exit", align);
        }
    }
}

class RingDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onSelect() as Boolean { return true; }
    function onMenu() as Boolean { return true; }
    function onBack() as Boolean {
        (WatchUi.getCurrentView()[0] as RingView).cancel();
        return true;
    }
}
