import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Vector crescent shared by the main-screen shortcut and the sleep screen.
module SleepIcon {
    function draw(dc, x, y, radius, foreground, background) as Void {
        dc.setColor(foreground, background);
        dc.fillCircle(x, y, radius);
        dc.setColor(background, background);
        dc.fillCircle(x + radius * 0.55, y - radius * 0.35, radius * 0.9);
    }
}

// Remains in the foreground: the app's scheduler opens RingView directly.
// No sensor subscription, activity recording, or display timer while asleep.
class SleepView extends WatchUi.View {
    private var _deadline as Number;

    function initialize(deadline as Number) {
        View.initialize();
        _deadline = deadline;
    }

    function onShow() as Void { dim(); }

    function onHide() as Void {
        if (Attention has :backlight) { Attention.backlight(true); }
    }

    function dim() as Void {
        if (Attention has :backlight) { Attention.backlight(false); }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var color = w >= 240;
        var fg = color ? 0x888888 : Graphics.COLOR_WHITE;
        var muted = color ? 0x555555 : Graphics.COLOR_WHITE;
        var bg = Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();
        SleepIcon.draw(dc, color ? w / 2 : w * 0.35, h * 0.18, color ? 9 : 8, muted, bg);

        var info = Gregorian.info(new Time.Moment(_deadline), Time.FORMAT_SHORT);
        var full = Gregorian.info(new Time.Moment(_deadline), Time.FORMAT_MEDIUM);
        var use24 = System.getDeviceSettings().is24Hour;
        var hour = use24 ? info.hour : info.hour % 12;
        if (!use24 && hour == 0) { hour = 12; }
        var time = hour.format(use24 ? "%02d" : "%d") + ":" + info.min.format("%02d");
        var period = use24 ? "" : (info.hour >= 12 ? " PM" : " AM");
        var align = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(muted, bg);
        dc.drawText(color ? w / 2 : w * 0.35, h * 0.36, Graphics.FONT_XTINY, "NEXT ALARM", align);
        dc.setColor(fg, bg);
        dc.drawText(w / 2, h * 0.52, Graphics.FONT_NUMBER_MEDIUM, time, align);
        dc.setColor(muted, bg);
        dc.drawText(w / 2, h * 0.64, Graphics.FONT_XTINY, period, align);
        dc.drawText(w / 2, h * 0.74, Graphics.FONT_XTINY,
            full.day_of_week + " " + info.day.toString() + " " + full.month, align);
        dc.drawText(w / 2, h * 0.86, Graphics.FONT_XTINY, "BACK = return", align);
    }
}

class SleepDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onKeyPressed(event as WatchUi.KeyEvent) as Boolean {
        if (event.getKey() == WatchUi.KEY_LIGHT || event.getKey() == WatchUi.KEY_POWER) {
            return stayAsleep();
        }
        return false;
    }
    function onKeyReleased(event as WatchUi.KeyEvent) as Boolean { return onKeyPressed(event); }
    function onKey(event as WatchUi.KeyEvent) as Boolean { return onKeyPressed(event); }
    private function stayAsleep() as Boolean {
        (WatchUi.getCurrentView()[0] as SleepView).dim();
        return true;
    }
    function onSelect() as Boolean { return stayAsleep(); }
    function onPreviousPage() as Boolean { return stayAsleep(); }
    function onNextPage() as Boolean { return stayAsleep(); }
    function onMenu() as Boolean { return stayAsleep(); }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return stayAsleep(); }
    function onBack() as Boolean {
        getApp().finishSleep();
        return true;
    }
}
