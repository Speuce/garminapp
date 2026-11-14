import Toybox.Application.Storage;
import Toybox.Lang;

// This adapter uses the device filesystem, not AppBase's in-memory property store.
class DeviceAlarmStorage {
    function initialize() {}
    function read(key) { return Storage.getValue(key); }
    function write(key, value) { Storage.setValue(key, value); }
}

class AlarmStore {
    static const STORAGE_KEY = "jumpstart.alarms.v1";
    static const MAX_ALARMS = 16;
    var records as Array<Dictionary> = [];
    var error = null;
    var readable = false;
    private var _storage as DeviceAlarmStorage;
    private var _key as String;
    private var _nextId = 1;

    function initialize(storage as DeviceAlarmStorage, key as String) {
        _storage = storage;
        _key = key;
        load();
    }

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
