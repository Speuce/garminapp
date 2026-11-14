import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Instinct 2: 176x176 monochrome, with a 62px subwindow at (113, 0).
// Keep the heading left of that window and full-width content below its bezel.
// This view uses only API 3.4 graphics; navigation and storage remain shared.
class TrailView extends WatchUi.View {
    const FG = Graphics.COLOR_WHITE;
    const BG = Graphics.COLOR_BLACK;
    private var _c as AlarmController;

    function initialize(controller as AlarmController) {
        View.initialize();
        _c = controller;
    }

    function hitSleep(x, y) as Boolean {
        return _c.state == AlarmController.LIST && x >= 124 && x <= 164 && y >= 11 && y <= 51;
    }

    private function text(dc, value, x, y, font, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function fit(dc, value, width) {
        if (dc.getTextWidthInPixels(value, Graphics.FONT_XTINY) <= width) { return value; }
        while (value.length() > 0 && dc.getTextWidthInPixels(value + "..", Graphics.FONT_XTINY) > width) {
            value = value.substring(0, value.length() - 1);
        }
        return value + "..";
    }

    private function header(dc, label, badge) {
        text(dc, label, 62, 30, Graphics.FONT_XTINY, FG);
        // The watch bezel supplies the subwindow outline; do not draw over it.
        text(dc, badge, 144, 31, Graphics.FONT_XTINY, FG);
    }

    private function noticeLabel(message) {
        var labels = {
            "Choose at least one day" => "Select a day",
            "Saved to device" => "Saved",
            "Alarm enabled" => "Enabled",
            "Alarm disabled" => "Disabled",
            "Alarm deleted" => "Deleted",
            "Maximum 16 alarms" => "Limit: 16",
            "Alarm limit reached" => "Limit: 16",
            "Alarm no longer exists" => "Alarm missing",
            "Set an alarm first" => "Set an alarm",
            "Invalid alarm settings" => "Invalid alarm",
            "Save not confirmed" => "Unconfirmed"
        };
        return labels.hasKey(message) ? labels[message] : message;
    }

    private function row(dc, label, y, selected) {
        dc.setColor(selected ? FG : BG, BG);
        dc.fillRoundedRectangle(26, y - 13, 124, 27, 3);
        text(dc, label, 88, y, Graphics.FONT_XTINY, selected ? BG : FG);
    }

    private function menuRows(dc, labels as Array<String>, selected) {
        var first = selected < 3 ? 0 : selected - 2;
        for (var i = first; i < labels.size() && i < first + 3; i++) {
            row(dc, labels[i], 85 + (i - first) * 27, i == selected);
        }
    }

    private function hints(dc, menu, save) {
        dc.setColor(FG, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (menu) {
            dc.drawArc(88, 88, 85, Graphics.ARC_CLOCKWISE, 190, 170);
            // Three dots by UP indicate the hold-menu action without tiny rotated text.
            for (var i = 0; i < 3; i++) { dc.fillCircle(10, 82 + i * 5, 1); }
        }
        if (save) {
            dc.drawArc(144, 31, 28, Graphics.ARC_CLOCKWISE, 20, -20);
        }
        dc.setPenWidth(1);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(BG, BG);
        dc.clear();
        if (!_c.store.readable) {
            header(dc, "Storage", "!");
            text(dc, "Data kept", 88, 84, Graphics.FONT_SMALL, FG);
            text(dc, "Select to retry", 88, 116, Graphics.FONT_XTINY, FG);
            hints(dc, false, false);
            return;
        }
        var state = _c.state;
        if (state == AlarmController.LIST) { drawList(dc); }
        else if (state == AlarmController.ACTIONS) {
            header(dc, "Actions", (_c.cursor + 1).toString() + "/6");
            var enabled = _c.store.records[_c.selection]["enabled"];
            menuRows(dc, ["Edit", enabled ? "Disable" : "Enable", "Delete", "Add alarm", "Test now", "Test in 5 min"], _c.cursor);
        } else if (state == AlarmController.TOOLS) {
            header(dc, "Test alarm", "GO");
            menuRows(dc, ["Test now", "Test in 5 min"], _c.cursor);
        } else if (state == AlarmController.HOUR || state == AlarmController.MINUTE || state == AlarmController.PERIOD) {
            drawTime(dc);
        } else if (state == AlarmController.PATTERN) {
            header(dc, "Repeat", (_c.cursor + 1).toString() + "/6");
            menuRows(dc, AlarmController.PATTERNS, _c.cursor);
        } else if (state == AlarmController.DAYS) { drawDays(dc); }
        else if (state == AlarmController.INTERVAL) {
            var unit = _c.draft["repeat"] == AlarmData.WEEKLY ? "week" : "day";
            header(dc, "Every", "N");
            text(dc, _c.draft["interval"].toString(), 88, 92, Graphics.FONT_NUMBER_MEDIUM, FG);
            text(dc, unit + (_c.draft["interval"] == 1 ? "" : "s"), 88, 127, Graphics.FONT_XTINY, FG);
        } else if (state == AlarmController.YEAR || state == AlarmController.MONTH || state == AlarmController.DAY) {
            drawDate(dc);
        } else if (state == AlarmController.REVIEW) { drawReview(dc); }
        else if (state == AlarmController.DELETE || state == AlarmController.DISCARD) { drawConfirmation(dc); }

        hints(dc, state == AlarmController.LIST || state == AlarmController.DAYS, state == AlarmController.REVIEW);
        if (_c.notice != null) {
            var message = noticeLabel(_c.notice);
            dc.setColor(BG, BG);
            dc.fillRectangle(21, 151, 134, 20);
            text(dc, fit(dc, message, 108), 88, 157, Graphics.FONT_XTINY, FG);
        }
    }

    private function drawList(dc) {
        var count = _c.store.records.size();
        var sleepSelected = _c.selection == AlarmController.SLEEP_SELECTION;
        header(dc, "JumpStart", "");
        if (sleepSelected) {
            dc.setColor(FG, BG);
            dc.drawCircle(144, 31, 16);
            SleepIcon.draw(dc, 144, 31, 8, FG, BG);
        }
        if (_c.selection == count || count == 0) {
            text(dc, count == 0 ? "No alarms yet" : "New alarm", 88, 81, Graphics.FONT_XTINY, FG);
            row(dc, "+ Add alarm", 120, !sleepSelected);
            return;
        }
        var item = _c.store.records[sleepSelected ? 0 : _c.selection];
        dc.setColor(FG, BG);
        if (sleepSelected) { dc.drawRoundedRectangle(22, 74, 132, 66, 4); }
        else { dc.fillRoundedRectangle(22, 74, 132, 66, 4); }
        var ink = sleepSelected ? FG : BG;
        text(dc, AlarmData.timeLabel(item), 77, 95, Graphics.FONT_NUMBER_MEDIUM, ink);
        text(dc, AlarmData.periodLabel(item), 137, 95, Graphics.FONT_XTINY, ink);
        text(dc, fit(dc, AlarmData.repeatLabel(item), 124), 88, 125, Graphics.FONT_XTINY, ink);
        if (!sleepSelected && !item["enabled"]) { text(dc, "Disabled", 88, 155, Graphics.FONT_XTINY, FG); }
    }

    private function drawTime(dc) {
        var a = _c.draft;
        var state = _c.state;
        header(dc, state == AlarmController.HOUR ? "Set hour" : (state == AlarmController.MINUTE ? "Set minute" : "AM / PM"), AlarmData.periodLabel(a));
        var hour = a["hour"] % 12;
        if (hour == 0) { hour = 12; }
        // Inversion is the monochrome equivalent of Trail's lime selected field.
        var hourSelected = state == AlarmController.HOUR;
        var minuteSelected = state == AlarmController.MINUTE;
        dc.setColor(hourSelected ? FG : BG, BG);
        dc.fillRoundedRectangle(24, 72, 54, 45, 3);
        dc.setColor(minuteSelected ? FG : BG, BG);
        dc.fillRoundedRectangle(98, 72, 54, 45, 3);
        text(dc, hour.format("%02d"), 51, 94, Graphics.FONT_NUMBER_MEDIUM, hourSelected ? BG : FG);
        text(dc, ":", 88, 94, Graphics.FONT_NUMBER_MEDIUM, FG);
        text(dc, a["minute"].format("%02d"), 125, 94, Graphics.FONT_NUMBER_MEDIUM, minuteSelected ? BG : FG);
        if (state == AlarmController.PERIOD) {
            row(dc, AlarmData.periodLabel(a), 135, true);
        }
    }

    private function drawDays(dc) {
        header(dc, "Days", _c.cursor == 7 ? "OK" : AlarmData.DAY_NAMES[_c.cursor]);
        // Two rows of day cells avoid shrinking seven glyphs into the small display.
        for (var i = 0; i < 7; i++) {
            var x = i < 4 ? 40 + i * 32 : 56 + (i - 4) * 32;
            var y = i < 4 ? 86 : 115;
            var selected = (_c.draft["days"] & (1 << i)) != 0;
            dc.setColor(selected ? FG : BG, BG);
            dc.fillRoundedRectangle(x - 11, y - 10, 23, 22, 2);
            text(dc, AlarmData.DAY_NAMES[i].substring(0, 1), x, y, Graphics.FONT_XTINY, selected ? BG : FG);
            if (i == _c.cursor) {
                dc.setColor(FG, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(x - 14, y - 13, 29, 28, 2);
            }
        }
        if (_c.notice == null) { row(dc, "Done", 145, _c.cursor == 7); }
    }

    private function drawDate(dc) {
        var state = _c.state;
        var field = state == AlarmController.YEAR ? "year" : (state == AlarmController.MONTH ? "month" : "day");
        header(dc, "Date", field.substring(0, 1).toUpper());
        text(dc, _c.draft[field].toString(), 88, 92, Graphics.FONT_NUMBER_MEDIUM, FG);
        text(dc, AlarmData.dateLabel(_c.draft), 88, 129, Graphics.FONT_XTINY, FG);
    }

    private function drawReview(dc) {
        var a = _c.draft;
        header(dc, "Review", "SAVE");
        text(dc, AlarmData.timeLabel(a), 77, 83, Graphics.FONT_NUMBER_MEDIUM, FG);
        text(dc, AlarmData.periodLabel(a), 141, 83, Graphics.FONT_XTINY, FG);
        text(dc, fit(dc, AlarmData.repeatLabel(a), 138), 88, 114, Graphics.FONT_XTINY, FG);
        if (a["repeat"] == AlarmData.WEEKLY && a["interval"] > 1) {
            text(dc, "Every " + a["interval"].toString() + " weeks", 88, 134, Graphics.FONT_XTINY, FG);
        } else {
            text(dc, a["repeat"] == AlarmData.ONCE ? AlarmData.dateLabel(a) : (a["enabled"] ? "Enabled" : "Disabled"),
                88, 140, Graphics.FONT_XTINY, FG);
        }
    }

    private function drawConfirmation(dc) {
        var deleting = _c.state == AlarmController.DELETE;
        var a = deleting ? _c.store.records[_c.selection] : _c.draft;
        header(dc, deleting ? "Delete?" : "Discard?", "?");
        text(dc, AlarmData.timeLabel(a) + " " + AlarmData.periodLabel(a), 88, 77, Graphics.FONT_XTINY, FG);
        row(dc, deleting ? "Keep alarm" : "Keep editing", 110, _c.cursor == 0);
        row(dc, deleting ? "Delete" : "Discard", 141, _c.cursor == 1);
    }
}
