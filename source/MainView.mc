import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class MainView extends WatchUi.View {

    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        // If the alarm time arrives while the app is open, start ringing.
        if (AlarmStore.isRinging()) {
            WatchUi.switchToView(new RingView(false), new RingDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.30, h * 0.10, Graphics.FONT_XTINY,
            "Now " + AlarmStore.formatTime(now.hour, now.min),
            Graphics.TEXT_JUSTIFY_CENTER);

        var on = AlarmStore.isEnabled() || AlarmStore.isTestPending();
        var fireAt = AlarmStore.getFireAt();
        var alarmTime = AlarmStore.formatTime(AlarmStore.getHour(), AlarmStore.getMinute());
        if (AlarmStore.isTestPending() && fireAt != null) {
            var testTime = Gregorian.info(new Time.Moment(fireAt), Time.FORMAT_SHORT);
            alarmTime = AlarmStore.formatTime(testTime.hour, testTime.min);
        }
        dc.drawText(w / 2, h * 0.38, Graphics.FONT_NUMBER_HOT, alarmTime,
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.65, Graphics.FONT_SMALL,
            AlarmStore.isTestPending() ? "TEST ARMED" : (on ? "ALARM ON" : "ALARM OFF"),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Keep the next scheduled time visible, including a one-off device test.
        var sched = "Not scheduled";
        if (on && fireAt != null) {
            var f = Gregorian.info(new Time.Moment(fireAt), Time.FORMAT_SHORT);
            sched = "Next " + AlarmStore.formatTime(f.hour, f.min);
        }
        dc.drawText(w / 2, h * 0.76, Graphics.FONT_XTINY, sched, Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.86, Graphics.FONT_XTINY, "START = menu", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class MainDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        openMenu();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        openMenu();
        return true;
    }

    private function openMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Alarm"});
        menu.addItem(new WatchUi.ToggleMenuItem("Enabled", null, :toggle,
            AlarmStore.isEnabled(), null));
        menu.addItem(new WatchUi.MenuItem("Set time",
            AlarmStore.formatTime(AlarmStore.getHour(), AlarmStore.getMinute()),
            :setTime, null));
        menu.addItem(new WatchUi.MenuItem("Test ring", "Ring screen now", :testRing, null));
        menu.addItem(new WatchUi.MenuItem("Test in 5 min", "One alarm only", :testLater, null));
        WatchUi.pushView(menu, new AlarmMenuDelegate(), WatchUi.SLIDE_LEFT);
    }
}

class AlarmMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :toggle) {
            AlarmStore.setEnabled((item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :setTime) {
            WatchUi.pushView(new TimePickerView(), new TimePickerDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :testRing) {
            WatchUi.switchToView(new RingView(true), new RingDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :testLater) {
            AlarmStore.scheduleTest(300);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
