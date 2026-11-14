import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Full-screen ringing view: vibrates + beeps until dismissed or snoozed.
class RingView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _jumpTimer as Timer.Timer?;
    private var _jumps as Number = 0;
    private var _font as Graphics.VectorFont?;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _font = Graphics.getVectorFont({
            :face => ["RobotoCondensedBold", "RobotoRegular"],
            :size => 24
        });
    }

    function onShow() as Void {
        _jumps = 0;

        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1500, true);

        // SIMULATED jumps: +1 every 2 seconds.
        // When real jump detection exists, remove this timer and call addJump()
        // from the detector instead.
        _jumpTimer = new Timer.Timer();
        _jumpTimer.start(method(:onJumpTick), 1000, true);

        alert();
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (_jumpTimer != null) {
            _jumpTimer.stop();
            _jumpTimer = null;
        }
        if (Attention has :vibrate) {
            Attention.vibrate([] as Array<Attention.VibeProfile>);   // stop vibration
        }
    }

    function onTick() as Void {
        alert();
        WatchUi.requestUpdate();
    }

    function onJumpTick() as Void {
        addJump();
        WatchUi.requestUpdate();
    }

    // Hook for the future jump detector.
    function addJump() as Void {
        _jumps += 1;
    }

    private function getHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        // Fallback: most recent stored sample (can be a bit old)
        if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            var sample = it.next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    private function alert() as Void {
        if (Attention has :backlight) {
            Attention.backlight(true);
        }
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 400)
            ] as Array<Attention.VibeProfile>);
        }
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALARM);
        }
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        // var cy = h / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_RED);
        dc.clear();

        // // --- curved stop bar by the START/STOP button ---
        // var buttonAngle = 30;     // 0 = 3 o'clock, counter-clockwise positive
        // var span = 26;            // half the arc length of the bar, in degrees
        // var penW = 14;

        // dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // dc.setPenWidth(penW);
        // dc.drawArc(cx, cy, w / 2 - penW / 2, Graphics.ARC_CLOCKWISE,
        //            buttonAngle + span, buttonAngle - span);
        // dc.setPenWidth(1);

        // if (_font != null) {
        //     var textR = w / 2 - penW - 6 - dc.getFontHeight(_font);
        //     dc.drawRadialText(cx, cy, _font, "stop",
        //         Graphics.TEXT_JUSTIFY_CENTER,
        //         buttonAngle, textR,
        //         Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
        // }

        // --- alarm time ---
        dc.drawText(cx, h * 0.16, Graphics.FONT_MEDIUM, "WAKE UP LAZY", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.30, Graphics.FONT_NUMBER_HOT,
            AlarmStore.formatTime(AlarmStore.getHour(), AlarmStore.getMinute()),
            Graphics.TEXT_JUSTIFY_CENTER);

        // --- jump counter (left) and heart rate (right) ---
        var labelY = h * 0.67;
        var valueY = h * 0.75;
        var leftX  = w * 0.30;
        var rightX = w * 0.70;

        var hr = getHeartRate();
        var hrText = (hr != null) ? hr.toString() : "--";

        dc.drawText(leftX,  labelY, Graphics.FONT_TINY,   "JUMPS", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(leftX,  valueY, Graphics.FONT_MEDIUM, _jumps.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(rightX, labelY, Graphics.FONT_TINY,   "HR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, valueY, Graphics.FONT_MEDIUM, hrText, Graphics.TEXT_JUSTIFY_CENTER);

        // --- jumping-jack critter between the two readouts ---
        // Pose flips on every jump, so it will follow real jumps once detection exists.
        drawJumper(dc, cx, h * 0.77, (_jumps % 2) == 1);
    }

    // Small cat-like critter doing a jumping jack. (x, y) is the center of its body.
    private function drawJumper(dc as Dc, x as Numeric, y as Numeric, armsUp as Boolean) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);

        // limbs (drawn first so the body sits on top)
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

        // body, head, ears
        dc.fillEllipse(x, y + 2, 6, 9);
        dc.fillCircle(x, y - 14, 7);
        // dc.fillPolygon([[x - 7, y - 17], [x - 6, y - 26], [x - 1, y - 20]] as Array<Point2D>);
        // dc.fillPolygon([[x + 7, y - 17], [x + 6, y - 26], [x + 1, y - 20]] as Array<Point2D>);

        // eyes (background color)
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y - 15, 2);
        dc.fillCircle(x + 3, y - 15, 2);

        dc.setPenWidth(1);
    }

}

class RingDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {         // START: stop
        stopAlarm();
        return true;
    }

    private function stopAlarm() as Void {
        AlarmStore.dismiss();
        WatchUi.switchToView(new MainView(), new MainDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}
