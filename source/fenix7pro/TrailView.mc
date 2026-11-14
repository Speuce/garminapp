import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Coordinates target the project's 260px fenix 7 Pro display. Content stays
// inside the outer 22px band reserved for contextual button hints.
class TrailView extends WatchUi.View {
    const BG = 0x10150F;
    const WHITE = 0xF1F5E9;
    const LIME = 0xCCFF66;
    const MUTED = 0xAAAA99;
    const PANEL = 0x26331A;
    const DANGER = 0xFFAA55;
    private var _c as AlarmController;
    private var _rimFont = null;

    function initialize(controller as AlarmController) {
        View.initialize();
        _c = controller;
    }

    function hitSleep(x, y) as Boolean {
        return _c.state == AlarmController.LIST && x >= 181 && x <= 220 && y >= 23 && y <= 62;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        if (Graphics has :getVectorFont) {
            _rimFont = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoRegular", "Swiss721Regular"], :size => 11});
        }
    }

    private function text(dc, value, y, font, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(130, y, font, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function title(dc, value) { text(dc, value, 29, Graphics.FONT_TINY, LIME); }

    private function row(dc, value, y, selected, destructive) {
        dc.setColor(selected ? PANEL : BG, BG);
        dc.fillRoundedRectangle(44, y, 172, 37, 7);
        if (selected) {
            dc.setColor(destructive ? DANGER : LIME, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(44, y + 5, 3, 27, 1);
        }
        text(dc, value, y + 6, Graphics.FONT_SMALL, destructive ? DANGER : (selected ? WHITE : MUTED));
    }

    private function menuRows(dc, labels as Array<String>, selected, top) {
        var first = selected < 3 ? 0 : selected - 2;
        for (var i = first; i < labels.size() && i < first + 3; i++) {
            row(dc, labels[i], top + (i - first) * 43, i == selected, labels[i].equals("Delete"));
        }
        text(dc, (selected + 1).toString() + " / " + labels.size().toString(), 207, Graphics.FONT_XTINY, MUTED);
    }

    private function edge(dc, label, angle, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawArc(130, 130, 125, Graphics.ARC_CLOCKWISE, angle + 10, angle - 10);
        dc.setPenWidth(1);
        if (_rimFont != null && dc has :drawRadialText) {
            dc.drawRadialText(130, 130, _rimFont, label, Graphics.TEXT_JUSTIFY_CENTER,
                angle, 111, Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
        } else {
            // Older firmware still gets curved markers with compact action symbols.
            var x = angle == 180 ? 16 : 228;
            var y = angle == 180 ? 120 : (angle > 0 ? 67 : 178);
            dc.drawText(x, y, Graphics.FONT_XTINY, angle == 180 ? "=" : (angle > 0 ? "+" : "<"), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(BG, BG);
        dc.clear();
        if (!_c.store.readable) {
            title(dc, "Storage unavailable");
            text(dc, "Saved data kept", 94, Graphics.FONT_SMALL, WHITE);
            text(dc, "Select to retry", 135, Graphics.FONT_TINY, MUTED);
            edge(dc, "BACK", -35, MUTED);
            return;
        }

        var s = _c.state;
        if (s == AlarmController.LIST) { drawList(dc); }
        else if (s == AlarmController.ACTIONS) {
            title(dc, "Alarm actions");
            var enabled = _c.store.records[_c.selection]["enabled"];
            menuRows(dc, ["Edit", enabled ? "Disable" : "Enable", "Delete", "Add alarm", "Test now", "Test in 5 min"], _c.cursor, 65);
        } else if (s == AlarmController.TOOLS) {
            title(dc, "Test alarm");
            menuRows(dc, ["Test now", "Test in 5 min"], _c.cursor, 65);
        } else if (s == AlarmController.HOUR || s == AlarmController.MINUTE || s == AlarmController.PERIOD) {
            drawTime(dc);
        } else if (s == AlarmController.PATTERN) {
            title(dc, "Repeat");
            menuRows(dc, AlarmController.PATTERNS, _c.cursor, 65);
        } else if (s == AlarmController.DAYS) { drawDays(dc); }
        else if (s == AlarmController.INTERVAL) {
            title(dc, "Repeat every");
            text(dc, _c.draft["interval"].toString(), 84, Graphics.FONT_NUMBER_HOT, LIME);
            var unit = _c.draft["repeat"] == AlarmData.WEEKLY ? "week" : "day";
            text(dc, unit + (_c.draft["interval"] == 1 ? "" : "s"), 168, Graphics.FONT_SMALL, WHITE);
        } else if (s == AlarmController.YEAR || s == AlarmController.MONTH || s == AlarmController.DAY) {
            drawDate(dc);
        } else if (s == AlarmController.REVIEW) { drawReview(dc); }
        else if (s == AlarmController.DELETE || s == AlarmController.DISCARD) { drawConfirmation(dc); }

        if (s == AlarmController.LIST || s == AlarmController.DAYS) {
            edge(dc, s == AlarmController.DAYS ? "DONE - HOLD" : "MENU - HOLD", 180, LIME);
        }
        edge(dc, "BACK", -35, MUTED);
        if (s == AlarmController.REVIEW) { edge(dc, "SAVE", 35, LIME); }
        if (_c.notice != null) {
            dc.setColor(BG, BG);
            dc.fillRectangle(36, 207, 188, 19);
            text(dc, _c.notice, 208, Graphics.FONT_XTINY, LIME);
        }
    }

    private function drawList(dc) {
        dc.setColor(LIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(113, 29, Graphics.FONT_TINY, "JUMPSTART", Graphics.TEXT_JUSTIFY_CENTER);
        var sleepSelected = _c.selection == AlarmController.SLEEP_SELECTION;
        if (sleepSelected) { dc.drawCircle(200, 43, 11); }
        SleepIcon.draw(dc, 200, 43, 7, sleepSelected ? LIME : MUTED, BG);
        var items = _c.store.records;
        if (items.size() == 0) {
            text(dc, "No alarms yet", 90, Graphics.FONT_SMALL, MUTED);
            row(dc, "+ Add alarm", 137, !sleepSelected, false);
            return;
        }
        var first = sleepSelected ? 0 : (_c.selection / 2).toNumber() * 2;
        for (var i = first; i <= items.size() && i < first + 2; i++) {
            var y = 61 + (i - first) * 76;
            var selected = i == _c.selection;
            if (i == items.size()) { row(dc, "+ Add alarm", y + 10, selected, false); continue; }
            var item = items[i];
            dc.setColor(selected ? PANEL : BG, BG);
            dc.fillRoundedRectangle(43, y, 174, 72, 8);
            if (selected) {
                dc.setColor(LIME, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(43, y, 174, 72, 8);
            }
            dc.setColor(item["enabled"] ? WHITE : MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(55, y - 11, Graphics.FONT_NUMBER_MEDIUM, AlarmData.timeLabel(item), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(203, y + 12, Graphics.FONT_XTINY, AlarmData.periodLabel(item), Graphics.TEXT_JUSTIFY_RIGHT);
            text(dc, (item["enabled"] ? "" : "OFF / ") + AlarmData.repeatLabel(item), y + 48, Graphics.FONT_XTINY, MUTED);
        }
        text(dc, sleepSelected ? "Sleep" : (_c.selection + 1).toString() + " / " + (items.size() + 1).toString(),
            210, Graphics.FONT_XTINY, MUTED);
    }

    private function drawTime(dc) {
        var a = _c.draft;
        var s = _c.state;
        title(dc, s == AlarmController.HOUR ? "Set hour" : (s == AlarmController.MINUTE ? "Set minute" : "AM / PM"));
        var hour = a["hour"] % 12;
        if (hour == 0) { hour = 12; }
        dc.setColor(s == AlarmController.HOUR ? LIME : WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(113, 89, Graphics.FONT_NUMBER_HOT, hour.format("%02d"), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(130, 89, Graphics.FONT_NUMBER_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(s == AlarmController.MINUTE ? LIME : WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(147, 89, Graphics.FONT_NUMBER_HOT, a["minute"].format("%02d"), Graphics.TEXT_JUSTIFY_LEFT);
        text(dc, AlarmData.periodLabel(a), 168, Graphics.FONT_SMALL, s == AlarmController.PERIOD ? LIME : MUTED);
    }

    private function drawDays(dc) {
        title(dc, "Repeat on");
        text(dc, _c.cursor < 7 ? AlarmData.DAY_NAMES[_c.cursor] : "Days selected", 70, Graphics.FONT_SMALL, WHITE);
        for (var i = 0; i < 7; i++) {
            var x = 52 + i * 26;
            var checked = (_c.draft["days"] & (1 << i)) != 0;
            dc.setColor(checked ? LIME : PANEL, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, 121, 10);
            dc.setColor(checked ? BG : MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, 112, Graphics.FONT_XTINY, AlarmData.DAY_NAMES[i].substring(0, 1), Graphics.TEXT_JUSTIFY_CENTER);
            if (i == _c.cursor) {
                dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, 121, 13);
            }
        }
        row(dc, "Done", 165, _c.cursor == 7, false);
    }

    private function drawDate(dc) {
        title(dc, "Alarm date");
        var s = _c.state;
        var field = s == AlarmController.YEAR ? "year" : (s == AlarmController.MONTH ? "month" : "day");
        text(dc, field.toUpper(), 69, Graphics.FONT_XTINY, MUTED);
        text(dc, _c.draft[field].toString(), 92, Graphics.FONT_NUMBER_HOT, LIME);
        text(dc, AlarmData.dateLabel(_c.draft), 166, Graphics.FONT_TINY, WHITE);
    }

    private function drawReview(dc) {
        var a = _c.draft;
        title(dc, "Review alarm");
        text(dc, AlarmData.timeLabel(a), 61, Graphics.FONT_NUMBER_HOT, WHITE);
        text(dc, AlarmData.periodLabel(a), 144, Graphics.FONT_XTINY, MUTED);
        text(dc, AlarmData.repeatLabel(a), 166, Graphics.FONT_TINY, LIME);
        var detail = a["enabled"] ? "Enabled" : "Disabled";
        if (a["repeat"] == AlarmData.ONCE) { detail = AlarmData.dateLabel(a); }
        else if (a["repeat"] == AlarmData.WEEKLY && a["interval"] > 1) {
            detail = "Every " + a["interval"].toString() + " weeks";
        }
        text(dc, detail, 193, Graphics.FONT_XTINY, MUTED);
    }

    private function drawConfirmation(dc) {
        var deleting = _c.state == AlarmController.DELETE;
        title(dc, deleting ? "Delete alarm?" : "Discard edits?");
        var item = deleting ? _c.store.records[_c.selection] : _c.draft;
        text(dc, AlarmData.timeLabel(item) + " " + AlarmData.periodLabel(item), 83, Graphics.FONT_SMALL, WHITE);
        row(dc, deleting ? "Keep alarm" : "Keep editing", 130, _c.cursor == 0, false);
        row(dc, deleting ? "Delete" : "Discard", 174, _c.cursor == 1, true);
    }
}
