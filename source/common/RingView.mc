import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class RingView extends WatchUi.View {
    private var _timer as Timer.Timer?;
    private var _animationTimer as Timer.Timer?;
    private var _armsUp as Boolean = false;
    private var _challenge as AlarmChallenge = new AlarmChallenge();
    private var _listening as Boolean = false;
    private var _sensorError as Boolean = false;
    private var _preview as Boolean;
    private var _receivedSamples as Boolean = false;
    private var _heart as HeartRateMonitor = new HeartRateMonitor(null);
    private var _trace as MotionTrace = new MotionTrace();

    function initialize(preview as Boolean) {
        View.initialize();
        _preview = preview;
    }

    function onShow() as Void {
        _challenge.start();
        _armsUp = false;
        _heart.start();
        _sensorError = false;
        _receivedSamples = false;
        _trace.start(_preview);
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
        _animationTimer = new Timer.Timer();
        _animationTimer.start(method(:onAnimationTick), 500, true);
        alert();
    }

    function onHide() as Void {
        _challenge.stop();
        _trace.stop();
        _heart.stop();
        if (_listening) {
            Sensor.unregisterSensorDataListener();
            _listening = false;
        }
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (_animationTimer != null) {
            _animationTimer.stop();
            _animationTimer = null;
        }
        if (Attention has :vibrate) {
            Attention.vibrate([] as Array<Attention.VibeProfile>);
        }
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (!_listening || accel == null) { return; }
        _receivedSamples = true;
        _trace.samples(accel.x, accel.y, accel.z);
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

    // Two half-second poses make one full jump per second, independent of reps.
    function onAnimationTick() as Void {
        _armsUp = !_armsUp;
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
            _trace.vibration();
            Attention.vibrate([
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 400)
            ] as Array<Attention.VibeProfile>);
        }
        if (Attention has :playTone) { Attention.playTone(Attention.TONE_ALARM); }
    }

    // Layout, top to bottom, each band has its own row so nothing overlaps:
    //   title / big count / "JUMPING JACKS" / [critter  <3 HR] / progress / status / exit
    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        // Match the Trail theme while preserving the Instinct's cutout layout.
        var color = w >= 240;
        var fg = color ? 0xF1F5E9 : Graphics.COLOR_WHITE;
        var bg = color ? 0x10150F : Graphics.COLOR_BLACK;
        var accent = color ? 0xCCFF66 : Graphics.COLOR_WHITE;
        var mid = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(fg, bg);
        dc.clear();

        var titleY  = h * (color ? 0.14 : 0.10);
        var countY  = h * (color ? 0.33 : 0.31);
        var labelY  = h * 0.49;
        var rowY    = h * (color ? 0.64 : 0.66);
        var barY    = h * 0.76;
        var statusY = h * (color ? 0.84 : 0.85);
        var exitY   = h * 0.93;

        dc.setColor(accent, bg);
        dc.drawText(color ? w / 2 : w * 0.30, titleY, Graphics.FONT_XTINY,
            _preview ? "TEST ALARM" : "WAKE UP", mid);
        dc.drawText(color ? w / 2 : w * 0.36, countY, Graphics.FONT_NUMBER_HOT,
            _challenge.count().toString() + "/" + _challenge.target().toString(), mid);

        dc.setColor(fg, bg);
        dc.drawText(w / 2, labelY, Graphics.FONT_XTINY, "JUMPING JACKS", mid);

        // Critter on the left, heart rate on the right, sharing one row.
        drawJumper(dc, w * 0.25, rowY, _armsUp, fg);
        HeartRateDisplay.draw(dc, w * 0.64, rowY, _heart.current(),
            Graphics.FONT_NUMBER_MEDIUM, fg, color ? 0xFF4D4D : fg, color);

        if (color) {
            dc.setColor(0x26331A, bg);
            dc.fillRoundedRectangle(w * 0.2, barY, w * 0.6, 5, 2);
            dc.setColor(accent, bg);
            dc.fillRoundedRectangle(w * 0.2, barY, w * 0.6 * _challenge.count() / _challenge.target(), 5, 2);
        }

        var status = !_receivedSamples ? "Stand still briefly" : "Keep going to stop";
        if (_sensorError) { status = "Sensor unavailable"; }
        dc.setColor(fg, bg);
        dc.drawText(w / 2, statusY, Graphics.FONT_XTINY, status, mid);
        if (_preview || _sensorError) {
            dc.drawText(w / 2, exitY, Graphics.FONT_XTINY, "BACK = exit", mid);
        }
    }

    // Jumping-jack critter (about 42px tall) centred on (x, y).
    // Pose follows the animation timer; only the detector can credit a rep.
    private function drawJumper(dc as Dc, x as Numeric, y as Numeric,
                                armsUp as Boolean, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);

        if (armsUp) {
            dc.drawLine(x - 5, y - 4, x - 15, y - 16);   // arms up
            dc.drawLine(x + 5, y - 4, x + 15, y - 16);
            dc.drawLine(x - 3, y + 9, x - 11, y + 20);   // legs apart
            dc.drawLine(x + 3, y + 9, x + 11, y + 20);
        } else {
            dc.drawLine(x - 5, y - 2, x - 9, y + 8);     // arms down
            dc.drawLine(x + 5, y - 2, x + 9, y + 8);
            dc.drawLine(x - 3, y + 9, x - 4, y + 21);    // legs together
            dc.drawLine(x + 3, y + 9, x + 4, y + 21);
        }

        dc.fillEllipse(x, y + 2, 6, 9);     // body
        dc.fillCircle(x, y - 14, 7);        // head

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y - 15, 2);    // eyes
        dc.fillCircle(x + 3, y - 15, 2);

        dc.setPenWidth(1);
    }
}

class RingDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    // Consume any LIGHT/POWER events delivered to the app. Firmware-owned
    // shortcuts (controls, assistance, shutdown) may never reach this delegate.
    function onKeyPressed(event as WatchUi.KeyEvent) as Boolean {
        return event.getKey() == WatchUi.KEY_LIGHT || event.getKey() == WatchUi.KEY_POWER;
    }
    function onKeyReleased(event as WatchUi.KeyEvent) as Boolean {
        return onKeyPressed(event);
    }
    function onKey(event as WatchUi.KeyEvent) as Boolean { return true; }
    function onSelect() as Boolean { return true; }
    function onMenu() as Boolean { return true; }
    function onPreviousPage() as Boolean { return true; }
    function onNextPage() as Boolean { return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return true; }
    function onBack() as Boolean {
        (WatchUi.getCurrentView()[0] as RingView).cancel();
        return true;
    }
}
