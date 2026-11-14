import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Forerunner 255 Music's native bitmap fonts have different metrics from fenix.
// All text is vertically centered in its own band, within the circular display.
class TrailView extends WatchUi.View {
    const BG = Graphics.COLOR_BLACK;
    const FG = Graphics.COLOR_WHITE;
    const ACCENT = 0xAAFF00;
    const MUTED = 0xAAAAAA;
    const PANEL = 0x005500;
    const DANGER = 0xFFAA00;
    private var _c as AlarmController;

    function initialize(controller as AlarmController) {
        View.initialize();
        _c = controller;
    }

    function hitSleep(x, y) as Boolean {
        return _c.state == AlarmController.LIST && x >= 175 && x <= 213 && y >= 15 && y <= 54;
    }

    private function text(dc, value, x, y, font, color) {
        dc.setColor(color, BG);
        dc.drawText(x, y, font, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function fitted(dc, value, y, width, color) {
        var font = Graphics.FONT_TINY;
        if (dc.getTextWidthInPixels(value, font) > width) { font = Graphics.FONT_XTINY; }
        if (dc.getTextWidthInPixels(value, font) > width) {
            while (value.length() > 0 && dc.getTextWidthInPixels(value + "..", font) > width) {
                value = value.substring(0, value.length() - 1);
            }
            value += "..";
        }
        text(dc, value, 130, y, font, color);
    }

    private function title(dc, value) { fitted(dc, value, 31, 165, ACCENT); }

    private function footer(dc, instruction, action) {
        var message = _c.notice == null ? instruction : _c.notice;
        if (message.length() > 0) {
            fitted(dc, message, 208, 186, _c.notice == null ? MUTED : ACCENT);
        }
        // At y=231 the circular screen only has about 164px of usable width.
        if (action.length() > 0) {
            text(dc, action, 130, 231, Graphics.FONT_XTINY, FG);
        }
    }

    private function row(dc, label, y, selected, destructive) {
        dc.setColor(selected ? PANEL : BG, BG);
        dc.fillRoundedRectangle(42, y - 17, 176, 34, 6);
        if (selected) {
            dc.setColor(destructive ? DANGER : ACCENT, BG);
            dc.drawRoundedRectangle(42, y - 17, 176, 34, 6);
        }
        // Transparent text background preserves the selection fill.
        dc.setColor(destructive ? DANGER : (selected ? FG : MUTED), Graphics.COLOR_TRANSPARENT);
        dc.drawText(130, y, Graphics.FONT_TINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Left-edge scroll bar: the thumb's position shows where UP/DOWN has put
    // the user in the list. x=18 / y=76..184 stays inside the circular bezel.
    private function scrollBar(dc, index, total) {
        if (total < 2) { return; }
        var top = 76;
        var trackH = 108;
        var thumbH = trackH / total;
        if (thumbH < 16) { thumbH = 16; }
        var thumbY = top + (trackH - thumbH) * index / (total - 1);
        dc.setColor(PANEL, BG);
        dc.fillRoundedRectangle(16, top, 5, trackH, 2);
        dc.setColor(ACCENT, BG);
        dc.fillRoundedRectangle(16, thumbY, 5, thumbH, 2);
    }

    private function menu(dc, labels as Array<String>, selected) {
        scrollBar(dc, selected, labels.size());
        var first = selected < 3 ? 0 : selected - 2;
        for (var i = first; i < labels.size() && i < first + 3; i++) {
            row(dc, labels[i], 79 + (i - first) * 40, i == selected, labels[i].equals("Delete"));
        }
        text(dc, (selected + 1).toString() + " / " + labels.size().toString(),
            130, 187, Graphics.FONT_XTINY, MUTED);
        footer(dc, "", "START: Select");
    }

    // A drawn pencil in the top-right, beside the START/STOP button that edits.
    private function editHint(dc) {
        var ox = 208;
        var oy = -58;
        dc.setColor(ACCENT, BG);
        dc.setPenWidth(2);
        dc.drawLine(ox + 9, oy + 131, ox + 19, oy + 121);
        dc.drawLine(ox + 13, oy + 135, ox + 23, oy + 125);
        dc.drawLine(ox + 19, oy + 121, ox + 23, oy + 125);
        dc.drawLine(ox + 9, oy + 131, ox + 8, oy + 136);
        dc.drawLine(ox + 8, oy + 136, ox + 13, oy + 135);
        dc.drawLine(ox + 17, oy + 123, ox + 21, oy + 127);
        dc.setPenWidth(1);
    }

    private function numberFont(dc, value, width) {
        return dc.getTextWidthInPixels(value, Graphics.FONT_NUMBER_HOT) <= width ?
            Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_MEDIUM;
    }

    private function drawList(dc) {
        text(dc, "JUMPSTART", 113, 31, Graphics.FONT_TINY, ACCENT);
        var sleepSelected = _c.selection == AlarmController.SLEEP_SELECTION;
        if (sleepSelected) {
            dc.setColor(ACCENT, BG);
            dc.drawCircle(193, 34, 11);
        }
        SleepIcon.draw(dc, 193, 34, 7, sleepSelected ? ACCENT : MUTED, BG);
        var items = _c.store.records;
        // The moon is a shortcut above the list, not a negative scroll position.
        if (!sleepSelected) { scrollBar(dc, _c.selection, items.size() + 1); }
        if (_c.selection >= items.size() || items.size() == 0) {
            fitted(dc, items.size() == 0 ? "No alarms yet" : "New alarm", 85, 180, MUTED);
            row(dc, "+ Add alarm", 130, !sleepSelected, false);
            footer(dc, "", sleepSelected ? "START: Sleep" : "START: Add");
            return;
        }
        var index = sleepSelected ? 0 : _c.selection;
        var item = items[index];
        text(dc, (index + 1).toString() + " / " + items.size().toString() +
            (item["enabled"] ? "   ON" : "   OFF"), 130, 59, Graphics.FONT_XTINY, MUTED);
        // One complete alarm per page gives the time and repeat rule ample room.
        var time = AlarmData.timeLabel(item);
        text(dc, time, 130, 109, numberFont(dc, time, 190), item["enabled"] ? FG : MUTED);
        text(dc, AlarmData.periodLabel(item), 130, 151, Graphics.FONT_XTINY, MUTED);
        fitted(dc, AlarmData.repeatLabel(item), 180, 185, ACCENT);
        if (!sleepSelected) { editHint(dc); }
        // Keep the clean layout while still explaining a failed sleep request.
        footer(dc, "", "");
    }

    private function drawTime(dc) {
        var state = _c.state;
        title(dc, state == AlarmController.HOUR ? "Set hour" :
            (state == AlarmController.MINUTE ? "Set minute" : "AM / PM"));
        var hour = _c.draft["hour"] % 12;
        if (hour == 0) { hour = 12; }
        var parts = [hour.format("%02d"), ":", _c.draft["minute"].format("%02d")];
        var font = numberFont(dc, parts[0] + parts[1] + parts[2], 190);
        var widths = [dc.getTextWidthInPixels(parts[0], font),
            dc.getTextWidthInPixels(parts[1], font), dc.getTextWidthInPixels(parts[2], font)];
        var x = (260 - widths[0] - widths[1] - widths[2]) / 2;
        for (var i = 0; i < 3; i++) {
            var active = (i == 0 && state == AlarmController.HOUR) ||
                (i == 2 && state == AlarmController.MINUTE);
            text(dc, parts[i], x + widths[i] / 2, 112, font, active ? ACCENT : FG);
            if (active) {
                dc.setColor(ACCENT, BG);
                dc.fillRectangle(x + 3, 150, widths[i] - 6, 3);
            }
            x += widths[i];
        }
        text(dc, AlarmData.periodLabel(_c.draft), 130, 177, Graphics.FONT_TINY,
            state == AlarmController.PERIOD ? ACCENT : MUTED);
        footer(dc, "", "START: Next");
    }

    private function drawDays(dc) {
        title(dc, "Repeat on");
        fitted(dc, _c.cursor < 7 ? AlarmData.DAY_NAMES[_c.cursor] : "Days selected", 76, 180, FG);
        for (var i = 0; i < 7; i++) {
            var x = 49 + i * 27;
            var checked = (_c.draft["days"] & (1 << i)) != 0;
            dc.setColor(checked ? ACCENT : PANEL, BG);
            dc.fillCircle(x, 120, 11);
            dc.setColor(checked ? BG : MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, 120, Graphics.FONT_XTINY, AlarmData.DAY_NAMES[i].substring(0, 1),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (i == _c.cursor) {
                dc.setColor(FG, BG);
                dc.drawCircle(x, 120, 14);
            }
        }
        row(dc, "Done", 169, _c.cursor == 7, false);
        footer(dc, "", _c.cursor == 7 ? "START: Next" : "START: Toggle");
    }

    private function drawDate(dc) {
        var state = _c.state;
        var field = state == AlarmController.YEAR ? "year" : (state == AlarmController.MONTH ? "month" : "day");
        title(dc, "Set " + field);
        text(dc, _c.draft[field].toString(), 130, 115, Graphics.FONT_NUMBER_MEDIUM, ACCENT);
        fitted(dc, AlarmData.dateLabel(_c.draft), 174, 180, FG);
        footer(dc, "", "START: Next");
    }

    private function drawReview(dc) {
        title(dc, "Review alarm");
        text(dc, AlarmData.timeLabel(_c.draft), 130, 85, Graphics.FONT_NUMBER_MEDIUM, FG);
        text(dc, AlarmData.periodLabel(_c.draft), 130, 119, Graphics.FONT_XTINY, MUTED);
        fitted(dc, AlarmData.repeatLabel(_c.draft), 150, 184, ACCENT);
        var detail = _c.draft["enabled"] ? "Enabled" : "Disabled";
        if (_c.draft["repeat"] == AlarmData.ONCE) { detail = AlarmData.dateLabel(_c.draft); }
        else if (_c.draft["repeat"] == AlarmData.WEEKLY && _c.draft["interval"] > 1) {
            detail = "Every " + _c.draft["interval"].toString() + " weeks";
        }
        fitted(dc, detail, 176, 184, MUTED);
        footer(dc, "BACK: change", "START: Save");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(BG, BG);
        dc.clear();
        if (!_c.store.readable) {
            title(dc, "Storage unavailable");
            fitted(dc, "Saved data kept", 113, 186, FG);
            footer(dc, "BACK: exit", "START: Retry");
            return;
        }
        var s = _c.state;
        if (s == AlarmController.LIST) { drawList(dc); }
        else if (s == AlarmController.ACTIONS) {
            title(dc, "Alarm options");
            menu(dc, ["Edit", _c.store.records[_c.selection]["enabled"] ? "Disable" : "Enable",
                "Delete", "Add alarm", "Test now", "Test in 5 min"], _c.cursor);
        } else if (s == AlarmController.TOOLS) {
            title(dc, "Test alarm");
            menu(dc, ["Test now", "Test in 5 min"], _c.cursor);
        } else if (s == AlarmController.HOUR || s == AlarmController.MINUTE || s == AlarmController.PERIOD) {
            drawTime(dc);
        } else if (s == AlarmController.PATTERN) {
            title(dc, "Repeat");
            menu(dc, AlarmController.PATTERNS, _c.cursor);
        } else if (s == AlarmController.DAYS) { drawDays(dc); }
        else if (s == AlarmController.INTERVAL) {
            title(dc, "Repeat every");
            text(dc, _c.draft["interval"].toString(), 130, 115, Graphics.FONT_NUMBER_MEDIUM, ACCENT);
            var unit = _c.draft["repeat"] == AlarmData.WEEKLY ? "week" : "day";
            fitted(dc, unit + (_c.draft["interval"] == 1 ? "" : "s"), 174, 180, FG);
            footer(dc, "", "START: Next");
        } else if (s == AlarmController.YEAR || s == AlarmController.MONTH || s == AlarmController.DAY) {
            drawDate(dc);
        } else if (s == AlarmController.REVIEW) { drawReview(dc); }
        else if (s == AlarmController.DELETE || s == AlarmController.DISCARD) {
            var deleting = s == AlarmController.DELETE;
            title(dc, deleting ? "Delete alarm?" : "Discard edits?");
            var item = deleting ? _c.store.records[_c.selection] : _c.draft;
            fitted(dc, AlarmData.timeLabel(item) + " " + AlarmData.periodLabel(item), 84, 180, FG);
            row(dc, deleting ? "Keep alarm" : "Keep editing", 128, _c.cursor == 0, false);
            row(dc, deleting ? "Delete" : "Discard", 169, _c.cursor == 1, true);
            footer(dc, "", "START: Select");
        }
    }
}
