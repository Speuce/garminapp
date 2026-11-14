import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Calendar rules are data only. This module does not calculate or trigger alarms.
(:background)
module AlarmData {
    const WEEKLY = 0;
    const INTERVAL = 1;
    const ONCE = 2;
    const FIELDS = ["id", "hour", "minute", "enabled", "repeat", "days", "interval", "year", "month", "day"];
    const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    function create() as Dictionary {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return {"id" => 0, "hour" => 7, "minute" => 0, "enabled" => true,
            "repeat" => WEEKLY, "days" => 31, "interval" => 1,
            "year" => today.year, "month" => today.month, "day" => today.day};
    }

    function copy(record as Dictionary) as Dictionary {
        var result = {};
        for (var i = 0; i < FIELDS.size(); i++) {
            result[FIELDS[i]] = record[FIELDS[i]];
        }
        return result;
    }

    function equal(a as Dictionary, b as Dictionary) as Boolean {
        for (var i = 0; i < FIELDS.size(); i++) {
            if (a[FIELDS[i]] != b[FIELDS[i]]) { return false; }
        }
        return true;
    }

    function inRange(value, low as Number, high as Number) as Boolean {
        return value instanceof Lang.Number && value >= low && value <= high;
    }

    function daysInMonth(year as Number, month as Number) as Number {
        if (month == 2) {
            return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28;
        }
        return (month == 4 || month == 6 || month == 9 || month == 11) ? 30 : 31;
    }

    function valid(record) as Boolean {
        if (!(record instanceof Lang.Dictionary)) { return false; }
        if (!inRange(record["id"], 0, 2147483646) ||
            !inRange(record["hour"], 0, 23) || !inRange(record["minute"], 0, 59) ||
            !(record["enabled"] instanceof Lang.Boolean) ||
            !inRange(record["repeat"], WEEKLY, ONCE) || !inRange(record["interval"], 1, 52) ||
            !inRange(record["days"], 1, 127) || !inRange(record["year"], 2020, 2099) ||
            !inRange(record["month"], 1, 12)) { return false; }
        return inRange(record["day"], 1, daysInMonth(record["year"], record["month"]));
    }

    function timeLabel(record as Dictionary) as String {
        var hour = record["hour"] % 12;
        if (hour == 0) { hour = 12; }
        return hour.format("%02d") + ":" + record["minute"].format("%02d");
    }

    function periodLabel(record as Dictionary) as String { return record["hour"] < 12 ? "AM" : "PM"; }

    function dateLabel(record as Dictionary) as String {
        return record["year"].format("%04d") + "-" + record["month"].format("%02d") + "-" + record["day"].format("%02d");
    }

    function dayLabel(mask as Number) as String {
        if (mask == 127) { return "Every day"; }
        if (mask == 31) { return "Mon - Fri"; }
        if (mask == 96) { return "Sat - Sun"; }
        var count = 0;
        var text = "";
        for (var i = 0; i < 7; i++) {
            if ((mask & (1 << i)) != 0) {
                if (count > 0) { text += ", "; }
                text += DAY_NAMES[i];
                count++;
            }
        }
        return count > 2 ? count.toString() + " days / week" : text;
    }

    function repeatLabel(record as Dictionary) as String {
        if (record["repeat"] == ONCE) { return "Once"; }
        if (record["repeat"] == INTERVAL) {
            return "Every " + record["interval"].toString() + (record["interval"] == 1 ? " day" : " days");
        }
        return dayLabel(record["days"]);
    }
}
