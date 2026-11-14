import Toybox.Lang;
import Toybox.Test;

(:test)
function oneTimeAndCapacity(logger as Test.Logger) as Boolean {
    var store = new AlarmStore(new MemoryAlarmStorage(), "test");
    var item = AlarmData.create();
    item["repeat"] = AlarmData.ONCE;
    item["year"] = 2028; item["month"] = 2; item["day"] = 29;
    Test.assert(store.save(item));
    Test.assertEqual(store.records[0]["repeat"], AlarmData.ONCE);
    Test.assertEqual(AlarmData.dateLabel(store.records[0]), "2028-02-29");
    for (var i = 1; i < AlarmStore.MAX_ALARMS; i++) { Test.assert(store.save(AlarmData.create())); }
    Test.assert(!store.save(AlarmData.create()));
    Test.assertEqual(store.records.size(), AlarmStore.MAX_ALARMS);
    var lastId = store.records[store.records.size() - 1]["id"];
    Test.assert(store.remove(lastId));
    Test.assert(store.save(AlarmData.create()));
    Test.assert(store.records[store.records.size() - 1]["id"] > lastId);
    return true;
}

(:test)
function saveFailureKeepsDraft(logger as Test.Logger) as Boolean {
    var backend = new MemoryAlarmStorage();
    var c = new AlarmController(new AlarmStore(backend, "test"));
    c.select(); c.select(); c.select(); c.select(); c.select();
    Test.assertEqual(c.state, AlarmController.REVIEW);
    backend.rejectWrites = true;
    c.select();
    Test.assertEqual(c.state, AlarmController.REVIEW);
    Test.assertEqual(c.store.records.size(), 0);
    Test.assertEqual(c.draft["hour"], 7);
    Test.assert(c.notice != null);
    backend.rejectWrites = false;
    c.select();
    Test.assertEqual(c.store.records.size(), 1);
    Test.assertEqual(c.state, AlarmController.LIST);
    return true;
}
