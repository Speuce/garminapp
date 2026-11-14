import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Simple two-step time picker: hour, then minute.
// UP/DOWN (or swipe) change the value, START moves on / saves, BACK cancels.
class TimePickerView extends WatchUi.View {

    var hour as Number;
    var minute as Number;
    var editingHour as Boolean = true;

    function initialize() {
        View.initialize();
        hour = AlarmStore.getHour();
        minute = AlarmStore.getMinute();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.30, h * 0.10, Graphics.FONT_XTINY,
            editingHour ? "Set hour" : "Set minute", Graphics.TEXT_JUSTIFY_CENTER);

        var hStr = hour.format("%02d");
        var mStr = minute.format("%02d");
        var cy = h * 0.38;

        // hour : minute, with the active field highlighted
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.40, cy, Graphics.FONT_NUMBER_HOT, hStr, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.50, cy, Graphics.FONT_NUMBER_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.60, cy, Graphics.FONT_NUMBER_HOT, mStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, "UP/DOWN change", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.86, Graphics.FONT_XTINY,
            editingHour ? "START = next" : "START = save", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function change(delta as Number) as Void {
        if (editingHour) {
            hour = (hour + delta + 24) % 24;
        } else {
            minute = (minute + delta + 60) % 60;
        }
        WatchUi.requestUpdate();
    }

    function advance() as Void {
        if (editingHour) {
            editingHour = false;
            WatchUi.requestUpdate();
        } else {
            AlarmStore.setTime(hour, minute);
            AlarmStore.setEnabled(true);   // setting a time turns the alarm on
            // Return to the main screen (pops picker and menu)
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}

class TimePickerDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    private function picker() as TimePickerView {
        return WatchUi.getCurrentView()[0] as TimePickerView;
    }

    function onPreviousPage() as Boolean {   // UP
        picker().change(1);
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        picker().change(-1);
        return true;
    }

    function onSelect() as Boolean {         // START
        picker().advance();
        return true;
    }

    function onBack() as Boolean {
        var p = picker();
        if (!p.editingHour) {
            p.editingHour = true;            // step back to hour first
            WatchUi.requestUpdate();
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
