import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Calendar calculations use local dates, not fixed 24-hour alarm intervals.
(:background)
module AlarmSchedule {
    // Civil day number; independent of timezone and daylight saving changes.
    function dayNumber(year, month, day) as Number {
        var y = year - (month <= 2 ? 1 : 0);
        var era = (y / 400).toNumber();
        var yo = y - era * 400;
        var m = month + (month > 2 ? -3 : 9);
        return era * 146097 + yo * 365 + (yo / 4).toNumber() -
            (yo / 100).toNumber() + ((153 * m + 2) / 5).toNumber() + day - 1;
    }

    function localMoment(year, month, day, hour, minute) as Time.Moment {
        // Gregorian.moment takes UTC fields. Invert Gregorian.info to obtain
        // the corresponding local wall time, including the device's offset.
        var wanted = Gregorian.moment({:year=>year, :month=>month, :day=>day,
            :hour=>hour, :minute=>minute, :second=>0});
        var result = wanted;
        for (var i = 0; i < 3; i++) {
            var info = Gregorian.info(result, Time.FORMAT_SHORT);
            var delta = (dayNumber(year, month, day) - dayNumber(info.year, info.month, info.day)) * 86400 +
                (hour - info.hour) * 3600 + (minute - info.min) * 60 - info.sec;
            if (delta == 0) { break; }
            result = result.add(new Time.Duration(delta));
        }
        return result;
    }

    function next(record as Dictionary, after as Number) as Number? {
        if (!record["enabled"]) { return null; }
        if (record["repeat"] == AlarmData.ONCE) {
            var once = localMoment(record["year"], record["month"], record["day"],
                record["hour"], record["minute"]).value();
            return once > after ? once : null;
        }
        var today = Gregorian.info(new Time.Moment(after), Time.FORMAT_SHORT);
        var day = Gregorian.moment({:year=>today.year, :month=>today.month, :day=>today.day,
            :hour=>0, :minute=>0, :second=>0});
        var anchor = dayNumber(record["year"], record["month"], record["day"]);
        if (dayNumber(today.year, today.month, today.day) < anchor - 7) {
            day = Gregorian.moment({:year=>record["year"], :month=>record["month"], :day=>record["day"],
                :hour=>0, :minute=>0, :second=>0});
        }
        // Day zero above is a Wednesday (March 1, year 0).
        var anchorMonday = anchor - ((anchor + 2) % 7);
        for (var i = 0; i <= 365; i++) {
            var date = Gregorian.utcInfo(day, Time.FORMAT_SHORT);
            var number = dayNumber(date.year, date.month, date.day);
            var weekday = (date.day_of_week + 5) % 7; // Monday = bit 0
            var matches = false;
            if (record["repeat"] == AlarmData.INTERVAL) {
                matches = number >= anchor && (number - anchor) % record["interval"] == 0;
            } else {
                var week = ((number - weekday - anchorMonday) / 7).toNumber();
                matches = week >= 0 && week % record["interval"] == 0 &&
                    (record["days"] & (1 << weekday)) != 0;
            }
            if (matches) {
                var at = localMoment(date.year, date.month, date.day, record["hour"], record["minute"]).value();
                if (at > after) { return at; }
            }
            day = day.add(new Time.Duration(86400));
        }
        return null;
    }

    // A one-time alarm means the next local occurrence of its clock time.
    // Advance the calendar date, rather than adding 24 hours to a local moment.
    function setNextOneTime(record as Dictionary, after as Number) as Void {
        var date = Gregorian.info(new Time.Moment(after), Time.FORMAT_SHORT);
        var at = localMoment(date.year, date.month, date.day, record["hour"], record["minute"]);
        if (at.value() <= after) {
            var day = Gregorian.moment({:year=>date.year, :month=>date.month, :day=>date.day,
                :hour=>0, :minute=>0, :second=>0}).add(new Time.Duration(86400));
            date = Gregorian.utcInfo(day, Time.FORMAT_SHORT);
        }
        record["repeat"] = AlarmData.ONCE;
        record["year"] = date.year;
        record["month"] = date.month;
        record["day"] = date.day;
    }
}

// Persist the selected occurrence so reopening at alarm time still rings.
// The adapter also lets simulator tests run without modifying real alarms.
class AlarmScheduler {
    static const KEY = "jumpstart.schedule.v1";
    static const RING_WINDOW = 600;
    var fireAt as Number? = null;
    var testAt as Number? = null;
    private var _applied as Number? = null;
    private var _store as AlarmStore;
    private var _storage as DeviceAlarmStorage;
    private var _revision as Number = -1;

    function initialize(store as AlarmStore, storage as DeviceAlarmStorage, now as Number) {
        _store = store;
        _storage = storage;
        var saved = storage.read(KEY);
        if (saved instanceof Dictionary) {
            fireAt = numeric(saved["fireAt"]);
            testAt = numeric(saved["testAt"]);
            _applied = numeric(saved["applied"]);
        }
        // A saved occurrence is only valid while its alarm still exists.
        var valid = fireAt != null && fireAt >= now - RING_WINDOW && fireAt == testAt;
        for (var i = 0; !valid && fireAt != null && i < store.records.size(); i++) {
            valid = fireAt >= now - RING_WINDOW && AlarmSchedule.next(store.records[i], fireAt - 1) == fireAt;
        }
        _revision = store.revision;
        if (!valid) { recompute(now); }
    }

    private function numeric(value) as Number? {
        return value instanceof Number || value instanceof Long ? value.toNumber() : null;
    }

    private function save() as Void {
        _storage.write(KEY, {"fireAt"=>fireAt, "testAt"=>testAt, "applied"=>_applied});
    }

    private function recompute(now as Number) as Void {
        fireAt = null;
        for (var i = 0; i < _store.records.size(); i++) {
            var at = AlarmSchedule.next(_store.records[i], now);
            if (at != null && (fireAt == null || at < fireAt)) { fireAt = at; }
        }
        if (testAt != null && testAt < now - RING_WINDOW) { testAt = null; }
        if (testAt != null && (fireAt == null || testAt < fireAt)) { fireAt = testAt; }
        _revision = _store.revision;
        save();
    }

    function refresh(now as Number) as Boolean {
        if (_revision != _store.revision || (fireAt != null && fireAt < now - RING_WINDOW)) {
            recompute(now);
            return true;
        }
        return false;
    }

    function due(now as Number) as Boolean {
        return fireAt != null && now >= fireAt && now < fireAt + RING_WINDOW;
    }

    function dismiss(now as Number) as Void {
        if (testAt != null && testAt <= now) { testAt = null; }
        // Disable completed one-time alarms; preserve all repeating settings.
        for (var i = 0; i < _store.records.size(); i++) {
            var item = _store.records[i];
            if (item["enabled"] && item["repeat"] == AlarmData.ONCE &&
                AlarmSchedule.next(item, now) == null) {
                _store.setEnabled(item["id"], false);
            }
        }
        recompute(now);
    }

    function armTest(deadline as Number, now as Number) as Void {
        testAt = deadline;
        recompute(now);
    }

    function applySideload(deadline, now as Number) as Void {
        var at = numeric(deadline);
        if (at == null || at <= now || at == _applied) { return; }
        _applied = at;
        armTest(at, now);
    }
}
