import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
class MemoryAlarmStorage extends DeviceAlarmStorage {
    var value = null;
    var rejectWrites = false;
    var writes = 0;
    function initialize() { DeviceAlarmStorage.initialize(); }
    function read(key) { return value; }
    function write(key, data) {
        writes++;
        if (!rejectWrites) { value = data; }
    }
}

(:test)
function alarmLifecycle(logger as Test.Logger) as Boolean {
    var backend = new MemoryAlarmStorage();
    var store = new AlarmStore(backend, "test");
    var first = AlarmData.create();
    Test.assert(store.save(first));
    Test.assertEqual(first["id"], 0); // Saving must not mutate the edit buffer.
    var second = AlarmData.create();
    second["hour"] = 8; second["minute"] = 30; second["days"] = 96;
    Test.assert(store.save(second));
    var id = store.records[0]["id"];
    Test.assert(store.setEnabled(id, false));
    var reopened = new AlarmStore(backend, "test");
    Test.assertEqual(reopened.records.size(), 2);
    Test.assertEqual(reopened.records[0]["enabled"], false);
    Test.assertEqual(reopened.records[1]["minute"], 30);
    var edit = AlarmData.copy(reopened.records[0]);
    edit["minute"] = 15;
    Test.assert(reopened.save(edit));
    Test.assertEqual(reopened.records[0]["enabled"], false);
    Test.assert(reopened.setEnabled(id, true));
    Test.assert(reopened.remove(id));
    Test.assertEqual(reopened.records.size(), 1);
    Test.assertEqual(reopened.records[0]["days"], 96);
    Test.assert(reopened.remove(reopened.records[0]["id"]));
    Test.assertEqual(new AlarmStore(backend, "test").records.size(), 0);
    return true;
}

(:test)
function failedWritesAndCorruptData(logger as Test.Logger) as Boolean {
    var backend = new MemoryAlarmStorage();
    var store = new AlarmStore(backend, "test");
    Test.assert(store.save(AlarmData.create()));
    backend.rejectWrites = true;
    var edit = AlarmData.copy(store.records[0]);
    edit["hour"] = 9;
    Test.assert(!store.save(edit));
    Test.assertEqual(store.records[0]["hour"], 7);
    Test.assert(!store.remove(store.records[0]["id"]));
    Test.assertEqual(store.records.size(), 1);
    backend.value = {"version" => 99, "alarms" => []};
    var broken = new AlarmStore(backend, "test");
    Test.assert(!broken.readable);
    var before = backend.writes;
    Test.assert(!broken.save(AlarmData.create()));
    Test.assertEqual(backend.writes, before);
    return true;
}

(:test)
function buttonSaveCancelDisableDelete(logger as Test.Logger) as Boolean {
    var backend = new MemoryAlarmStorage();
    var c = new AlarmController(new AlarmStore(backend, "test"));
    c.select(); // Add -> hour
    c.move(-1); // 08:00
    c.select(); c.select(); c.select(); // minute -> AM/PM -> repeat
    Test.assertEqual(c.state, AlarmController.PATTERN);
    c.select(); // Weekdays -> review
    Test.assertEqual(backend.writes, 0);
    c.select();
    Test.assertEqual(c.state, AlarmController.LIST);
    Test.assertEqual(c.store.records[0]["hour"], 8);
    c.select(); c.move(-1); c.back(); // Edit 9am, then discard prompt.
    c.move(1); c.select();
    Test.assertEqual(c.store.records[0]["hour"], 8);
    c.menu(); c.move(1); c.select(); // Disable
    Test.assertEqual(c.store.records[0]["enabled"], false);
    c.menu(); c.move(1); c.select(); // Enable
    Test.assertEqual(c.store.records[0]["enabled"], true);
    c.menu(); c.move(1); c.move(1); c.select(); // Delete prompt, default Keep
    Test.assertEqual(c.state, AlarmController.DELETE);
    c.select();
    Test.assertEqual(c.store.records.size(), 1);
    c.select(); c.move(1); c.select(); // Confirm delete
    Test.assertEqual(c.store.records.size(), 0);
    return true;
}

(:test)
function customRulesAndValidation(logger as Test.Logger) as Boolean {
    var c = new AlarmController(new AlarmStore(new MemoryAlarmStorage(), "test"));
    c.beginEdit(0);
    c.select(); c.select(); c.select();
    c.move(1); c.move(1); c.select(); // Weekdays -> custom week
    Test.assertEqual(c.state, AlarmController.DAYS);
    c.draft["days"] = 1;
    c.select(); // Can't remove the last day.
    Test.assertEqual(c.draft["days"], 1);
    c.menu(); // Done -> interval
    for (var i = 0; i < 4; i++) { c.move(-1); }
    Test.assertEqual(c.draft["interval"], 5);
    c.select();
    c.draft["year"] = 2028; c.draft["month"] = 2; c.draft["day"] = 29;
    c.move(-1); // 2029, clamp Feb 29 to Feb 28.
    Test.assertEqual(c.draft["day"], 28);
    c.select(); c.select(); c.select(); c.select();
    Test.assertEqual(c.store.records[0]["interval"], 5);
    Test.assertEqual(c.store.records[0]["days"], 1);
    var invalid = AlarmData.copy(c.store.records[0]);
    invalid["day"] = 30; invalid["month"] = 2;
    Test.assert(!c.store.save(invalid));
    invalid["day"] = 28; invalid["hour"] = 24;
    Test.assert(!AlarmData.valid(invalid));
    return true;
}

(:test)
function deviceStorageRoundTrip(logger as Test.Logger) as Boolean {
    // Separate key: tests must never replace the user's actual alarm list.
    var key = "jumpstart.test.roundtrip";
    Storage.deleteValue(key);
    var store = new AlarmStore(new DeviceAlarmStorage(), key);
    var item = AlarmData.create();
    item["minute"] = 42;
    item["repeat"] = AlarmData.INTERVAL;
    item["interval"] = 5;
    Test.assert(store.save(item));
    var reopened = new AlarmStore(new DeviceAlarmStorage(), key);
    Test.assertEqual(reopened.records[0]["minute"], 42);
    Test.assertEqual(reopened.records[0]["interval"], 5);
    Test.assert(reopened.setEnabled(reopened.records[0]["id"], false));
    Test.assertEqual(new AlarmStore(new DeviceAlarmStorage(), key).records[0]["enabled"], false);
    Storage.deleteValue(key);
    return true;
}

// Run these by name in separate simulator app launches to prove disk persistence.
(:test)
function persistenceStage1Write(logger as Test.Logger) as Boolean {
    var key = "jumpstart.test.restart";
    Storage.deleteValue(key);
    var store = new AlarmStore(new DeviceAlarmStorage(), key);
    var item = AlarmData.create();
    item["hour"] = 18; item["minute"] = 27; item["enabled"] = false;
    Test.assert(store.save(item));
    logger.debug("Restart probe written to Application.Storage.");
    return true;
}

(:test)
function persistenceStage2Read(logger as Test.Logger) as Boolean {
    var key = "jumpstart.test.restart";
    var store = new AlarmStore(new DeviceAlarmStorage(), key);
    Test.assertEqual(store.records.size(), 1);
    Test.assertEqual(store.records[0]["hour"], 18);
    Test.assertEqual(store.records[0]["minute"], 27);
    Test.assertEqual(store.records[0]["enabled"], false);
    Storage.deleteValue(key);
    logger.debug("Restart probe recovered from disk; scratch key removed.");
    return true;
}
