import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:test)
class ScheduleFixture {
    static function at(year, month, day, hour, minute) as Number {
        return AlarmSchedule.localMoment(year, month, day, hour, minute).value();
    }
    static function alarm() as Dictionary {
        var item = AlarmData.create();
        item["year"] = 2026; item["month"] = 11; item["day"] = 2;
        item["hour"] = 7; item["minute"] = 15;
        return item;
    }
}
(:test)
class ScheduleMemory extends DeviceAlarmStorage {
    var values as Dictionary = {};
    function initialize() { DeviceAlarmStorage.initialize(); }
    function read(key) { return values[key]; }
    function write(key, value) { values[key] = value; }
}

(:test)
function weeklyAndIntervalSchedules(logger as Logger) as Boolean {
    var item = ScheduleFixture.alarm();
    var sat = ScheduleFixture.at(2026,11,14,8,0);
    Test.assertEqual(AlarmSchedule.next(item,sat), ScheduleFixture.at(2026,11,16,7,15));
    item["days"] = 96;
    Test.assertEqual(AlarmSchedule.next(item,sat), ScheduleFixture.at(2026,11,15,7,15));
    item["days"] = 1; item["interval"] = 2;
    Test.assertEqual(AlarmSchedule.next(item,ScheduleFixture.at(2026,11,9,0,0)), ScheduleFixture.at(2026,11,16,7,15));
    item["repeat"] = AlarmData.INTERVAL; item["interval"] = 3; item["day"] = 14;
    Test.assertEqual(AlarmSchedule.next(item,sat), ScheduleFixture.at(2026,11,17,7,15));
    item["year"] = 2028; item["month"] = 1; item["day"] = 1;
    Test.assertEqual(AlarmSchedule.next(item,sat), ScheduleFixture.at(2028,1,1,7,15));
    item["enabled"] = false;
    Test.assert(AlarmSchedule.next(item,sat) == null);
    return true;
}

(:test)
function calendarBoundariesAndLocalTime(logger as Logger) as Boolean {
    var item = ScheduleFixture.alarm(); item["days"] = 127;
    Test.assertEqual(AlarmSchedule.next(item,ScheduleFixture.at(2028,2,28,23,59)), ScheduleFixture.at(2028,2,29,7,15));
    Test.assertEqual(AlarmSchedule.next(item,ScheduleFixture.at(2026,12,31,23,59)), ScheduleFixture.at(2027,1,1,7,15));
    var local = Gregorian.info(new Time.Moment(ScheduleFixture.at(2026,11,14,13,5)), Time.FORMAT_SHORT);
    Test.assertEqual(local.hour,13); Test.assertEqual(local.min,5); Test.assertEqual(local.day,14);
    item["repeat"] = AlarmData.ONCE; item["year"] = 2028; item["month"] = 2; item["day"] = 29;
    var expected = ScheduleFixture.at(2028,2,29,7,15);
    Test.assertEqual(AlarmSchedule.next(item,expected-1), expected);
    Test.assert(AlarmSchedule.next(item,expected) == null);
    return true;
}

(:test)
function oneTimeAlarmUsesNextClockOccurrence(logger as Logger) as Boolean {
    var item = ScheduleFixture.alarm();
    var before = ScheduleFixture.at(2026,11,14,7,0);
    AlarmSchedule.setNextOneTime(item, before);
    Test.assertEqual(AlarmSchedule.next(item,before), ScheduleFixture.at(2026,11,14,7,15));
    var exact = ScheduleFixture.at(2026,11,14,7,15);
    AlarmSchedule.setNextOneTime(item, exact);
    Test.assertEqual(AlarmSchedule.next(item,exact), ScheduleFixture.at(2026,11,15,7,15));
    var leap = ScheduleFixture.at(2028,2,28,23,59);
    AlarmSchedule.setNextOneTime(item, leap);
    Test.assertEqual(AlarmSchedule.next(item,leap), ScheduleFixture.at(2028,2,29,7,15));
    var yearEnd = ScheduleFixture.at(2026,12,31,23,59);
    AlarmSchedule.setNextOneTime(item, yearEnd);
    Test.assertEqual(AlarmSchedule.next(item,yearEnd), ScheduleFixture.at(2027,1,1,7,15));
    return true;
}

(:test)
function listChangesRescheduleAndPersist(logger as Logger) as Boolean {
    var backend = new ScheduleMemory(); var store = new AlarmStore(backend,"alarms");
    var now = ScheduleFixture.at(2026,11,14,0,0);
    var scheduler = new AlarmScheduler(store,backend,now);
    Test.assert(scheduler.fireAt == null);
    var item = ScheduleFixture.alarm(); item["days"] = 127;
    Test.assert(store.save(item)); Test.assert(scheduler.refresh(now));
    var seven = ScheduleFixture.at(2026,11,14,7,15);
    Test.assertEqual(scheduler.fireAt,seven);
    item["hour"] = 6; Test.assert(store.save(item)); scheduler.refresh(now);
    Test.assertEqual(scheduler.fireAt,ScheduleFixture.at(2026,11,14,6,15));
    Test.assert(store.setEnabled(store.records[1]["id"],false)); scheduler.refresh(now);
    Test.assertEqual(scheduler.fireAt,seven);
    var reopened = new AlarmScheduler(new AlarmStore(backend,"alarms"),backend,seven+10);
    Test.assert(reopened.due(seven+10));
    reopened.dismiss(seven+10);
    Test.assertEqual(reopened.fireAt,ScheduleFixture.at(2026,11,15,7,15));
    Test.assert(!new AlarmScheduler(store,backend,seven+11).due(seven+11));
    store.remove(store.records[0]["id"]); scheduler.refresh(now);
    Test.assert(scheduler.fireAt == null);
    return true;
}

(:test)
function oneOffAndSimultaneousAlarms(logger as Logger) as Boolean {
    var backend = new ScheduleMemory(); var store = new AlarmStore(backend,"alarms");
    var now = ScheduleFixture.at(2026,11,14,7,0);
    var item = ScheduleFixture.alarm(); item["repeat"] = AlarmData.ONCE; item["day"] = 14;
    store.save(item); item["repeat"] = AlarmData.WEEKLY; item["days"] = 127; store.save(item);
    var scheduler = new AlarmScheduler(store,backend,now);
    scheduler.dismiss(now+901);
    Test.assertEqual(store.records[0]["enabled"],false);
    Test.assertEqual(store.records[1]["enabled"],true);
    Test.assertEqual(scheduler.fireAt,ScheduleFixture.at(2026,11,15,7,15));
    return true;
}

(:test)
function testAlarmPreservesListAndAppliesOnce(logger as Logger) as Boolean {
    var backend = new ScheduleMemory(); var store = new AlarmStore(backend,"alarms");
    var now = ScheduleFixture.at(2026,11,14,0,0);
    var item = ScheduleFixture.alarm(); item["days"] = 127; store.save(item);
    var scheduler = new AlarmScheduler(store,backend,now);
    scheduler.applySideload(now+300,now);
    Test.assertEqual(scheduler.fireAt,now+300); Test.assert(scheduler.due(now+300));
    scheduler.dismiss(now+301);
    Test.assertEqual(store.records.size(),1); Test.assertEqual(store.records[0]["enabled"],true);
    Test.assertEqual(scheduler.fireAt,ScheduleFixture.at(2026,11,14,7,15));
    var reopened = new AlarmScheduler(store,backend,now+302);
    reopened.applySideload(now+300,now+302);
    Test.assert(reopened.testAt == null);
    reopened.applySideload(now+900,now+302); Test.assertEqual(reopened.testAt,now+900);
    return true;
}

(:test)
function staleAndCancelledOccurrencesDoNotRing(logger as Logger) as Boolean {
    var backend = new ScheduleMemory(); var store = new AlarmStore(backend,"alarms");
    var item = ScheduleFixture.alarm(); item["days"] = 127; store.save(item);
    var now = ScheduleFixture.at(2026,11,14,7,0);
    var scheduler = new AlarmScheduler(store,backend,now);
    Test.assert(scheduler.fireAt != null);
    var stale = new AlarmScheduler(store,backend,now+1600);
    Test.assert(!stale.due(now+1600));
    Test.assertEqual(stale.fireAt,ScheduleFixture.at(2026,11,15,7,15));
    store.setEnabled(store.records[0]["id"],false);
    Test.assert(new AlarmScheduler(store,backend,now+901).fireAt == null);
    return true;
}
