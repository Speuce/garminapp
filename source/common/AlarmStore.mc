import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;

// This adapter uses the device filesystem, not AppBase's in-memory property store.
class DeviceAlarmStorage {
    function initialize() {}
    function read(key) { return Storage.getValue(key); }
    function write(key, value) { Storage.setValue(key, value); }
}

// Alarm settings, scheduling helpers and the saved alarm list, in one class.
//
//  * STATIC members  = the single "wake-up alarm" settings + scheduling.
//                      Call them without an instance: AlarmStore.getHour(),
//                      AlarmStore.snooze(), AlarmStore.formatTime(h, m) ...
//                      (so existing callers like RingView keep working).
//  * INSTANCE members = the validated, persisted list of alarm records.
//                      Create one with:
//                        var store = new AlarmStore(new DeviceAlarmStorage(), AlarmStore.STORAGE_KEY);
class AlarmStore {

    // ---------------------------------------------------------------- constants
    static const STORAGE_KEY = "jumpstart.alarms.v1";
    static const MAX_ALARMS = 16;
    static const RING_WINDOW_SEC = 600;   // alarm counts as "ringing" for 10 min
    static const SNOOZE_SEC = 540;        // 9 minutes (must be >= 5 min for temporal events)

    // ------------------------------------------------- instance state (records)
    var records as Array<Dictionary> = [];
    var error as String? = null;
    var readable as Boolean = false;
    private var _storage as DeviceAlarmStorage;
    private var _key as String;
    private var _nextId as Number = 1;

    function initialize(storage as DeviceAlarmStorage, key as String) {
        _storage = storage;
        _key = key;
        load();
    }

    // ============================================================================
    // Static: single alarm settings + scheduling
    // ============================================================================

    static function getHour() as Number {
        var v = Storage.getValue("hour");
        return (v instanceof Number) ? v : 7;
    }

    static function getMinute() as Number {
        var v = Storage.getValue("minute");
        return (v instanceof Number) ? v : 0;
    }

    static function isEnabled() as Boolean {
        var v = Storage.getValue("enabled");
        return (v instanceof Boolean) ? v : false;
    }

    static function setTime(hour as Number, minute as Number) as Void {
        Storage.setValue("hour", hour);
        Storage.setValue("minute", minute);
        reschedule();
    }

    // Single wake-up alarm on/off. (Named differently from the instance setEnabled(id, enabled)
    // below, because Monkey C has no overloading.)
    static function setWakeEnabled(on as Boolean) as Void {
        Storage.setValue("enabled", on);
        reschedule();
    }

    // Next occurrence of the configured time (local time), strictly in the future.
    static function nextMoment() as Moment {
        var offset = new Time.Duration(getHour() * 3600 + getMinute() * 60);
        var m = Time.today().add(offset);          // Time.today() = local midnight
        if (m.value() <= Time.now().value() + 60) {
            m = m.add(new Time.Duration(86400));
        }
        return m;
    }

    static function getFireAt() as Number or Null {
        var v = Storage.getValue("fireAt");
        return (v instanceof Number) ? v : null;
    }

    static function schedule(m as Moment) as Void {
        Storage.setValue("fireAt", m.value());
        try {
            Background.registerForTemporalEvent(m);
        } catch (e) {
            // Ignore: the alarm will be re-registered next time the app opens.
        }
    }

    static function reschedule() as Void {
        if (!isEnabled()) {
            Background.deleteTemporalEvent();
            Storage.deleteValue("fireAt");
            return;
        }
        schedule(nextMoment());
    }

    static function isRinging() as Boolean {
        var fireAt = getFireAt();
        if (!isEnabled() || fireAt == null) {
            return false;
        }
        var now = Time.now().value();
        return now >= fireAt && now < fireAt + RING_WINDOW_SEC;
    }

    static function dismiss() as Void {
        reschedule();   // next day's occurrence
    }

    static function snooze() as Void {
        schedule(Time.now().add(new Time.Duration(SNOOZE_SEC)));
    }

    static function formatTime(hour as Number, minute as Number) as String {
        return hour.format("%02d") + ":" + minute.format("%02d");
    }

    // ============================================================================
    // Instance: persisted list of alarm records
    // ============================================================================

    function load() {
        readable = false;
        try {
            var data = _storage.read(_key);
            if (data == null) {
                records = [];
                _nextId = 1;
            } else {
                if (!validSnapshot(data)) {
                    error = "Saved data unreadable";
                    return false;
                }
                records = (data as Dictionary)["alarms"];
                _nextId = (data as Dictionary)["nextId"];
            }
            readable = true;
            error = null;
            return true;
        } catch (e) {
            error = "Storage unavailable";
            return false;
        }
    }

    function validSnapshot(data) {
        if (!(data instanceof Lang.Dictionary) || data["version"] != 1 ||
            !AlarmData.inRange(data["nextId"], 1, 2147483647) ||
            !(data["alarms"] instanceof Lang.Array)) { return false; }
        var items = data["alarms"] as Array<Dictionary>;
        if (items.size() > MAX_ALARMS) { return false; }
        var ids = {};
        for (var i = 0; i < items.size(); i++) {
            var item = items[i] as Dictionary;
            if (!AlarmData.valid(item) || item["id"] < 1 || item["id"] >= data["nextId"] || ids.hasKey(item["id"])) {
                return false;
            }
            ids[item["id"]] = true;
        }
        return true;
    }

    function indexOf(id) {
        for (var i = 0; i < records.size(); i++) {
            if (records[i]["id"] == id) { return i; }
        }
        return -1;
    }

    private function copiedRecords() as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        for (var i = 0; i < records.size(); i++) { result.add(AlarmData.copy(records[i])); }
        return result;
    }

    // Publish the new in-memory state only after a device write and read-back agree.
    private function commit(items as Array<Dictionary>, nextId as Number) {
        if (!readable) { return false; } // Never overwrite unreadable or newer-schema data.
        var snapshot = {"version" => 1, "nextId" => nextId, "alarms" => items};
        if (!validSnapshot(snapshot)) { error = "Invalid alarm settings"; return false; }
        try {
            _storage.write(_key, snapshot);
            var saved = _storage.read(_key) as Dictionary;
            var verified = validSnapshot(saved) && saved["nextId"] == nextId && saved["alarms"].size() == items.size();
            if (verified) {
                var savedItems = saved["alarms"] as Array<Dictionary>;
                for (var i = 0; i < items.size(); i++) {
                    if (!AlarmData.equal(items[i], savedItems[i])) { verified = false; break; }
                }
            }
            if (!verified) { error = "Save not confirmed"; return false; }
            records = items;
            _nextId = nextId;
            error = null;
            return true;
        } catch (e) {
            error = "Could not save";
            return false;
        }
    }

    function save(draft as Dictionary) {
        if (!AlarmData.valid(draft)) { error = "Invalid alarm settings"; return false; }
        var items = copiedRecords();
        var nextId = _nextId;
        var item = AlarmData.copy(draft);
        if (item["id"] == 0) {
            if (items.size() >= MAX_ALARMS) { error = "Alarm limit reached"; return false; }
            item["id"] = nextId;
            nextId++;
            items.add(item);
        } else {
            var index = indexOf(item["id"]);
            if (index < 0) { error = "Alarm no longer exists"; return false; }
            items[index] = item;
        }
        return commit(items, nextId);
    }

    // Enable/disable one saved alarm record (used by AlarmController and the tests).
    function setEnabled(id, enabled) {
        var index = indexOf(id);
        if (index < 0) { error = "Alarm no longer exists"; return false; }
        var item = AlarmData.copy(records[index]);
        item["enabled"] = enabled;
        return save(item);
    }

    function remove(id) {
        if (indexOf(id) < 0) { error = "Alarm no longer exists"; return false; }
        var items = [] as Array<Dictionary>;
        for (var i = 0; i < records.size(); i++) {
            if (records[i]["id"] != id) { items.add(AlarmData.copy(records[i])); }
        }
        return commit(items, _nextId);
    }
}
