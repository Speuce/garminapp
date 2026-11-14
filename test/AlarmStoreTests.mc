import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

(:test)
class SavedAlarm {
    private var _keys as Array<String> = ["hour", "minute", "enabled", "fireAt", "testAlarm", "sideloadTestApplied"];
    private var _values as Array<Storage.ValueType>;
    function initialize() {
        _values = [];
        for (var i = 0; i < _keys.size(); i++) {
            _values.add(Storage.getValue(_keys[i]));
        }
    }
    function restore() as Void {
        AlarmStore.setEnabled(false);
        for (var i = 0; i < _keys.size(); i++) {
            if (_values[i] == null) { Storage.deleteValue(_keys[i]); }
            else { Storage.setValue(_keys[i], _values[i]); }
        }
        var fireAt = AlarmStore.getFireAt();
        if (fireAt != null && fireAt > Time.now().value()) {
            AlarmStore.schedule(new Time.Moment(fireAt));
        }
    }
}

(:test)
function oneOffAlarmRingsAndDismissesWhenDailyAlarmIsOff(logger as Logger) as Boolean {
    var saved = new SavedAlarm();
    try {
        AlarmStore.setEnabled(false);
        AlarmStore.scheduleTest(300);
        Test.assert(AlarmStore.isTestPending());
        Test.assert(!AlarmStore.isRinging());
        Test.assert(!AlarmStore.isEnabled());
        Storage.setValue("fireAt", Time.now().value() - 1);
        Test.assert(AlarmStore.isRinging());
        AlarmStore.dismiss();
        Test.assert(!AlarmStore.isRinging());
        Test.assert(!AlarmStore.isTestPending());
        Test.assert(AlarmStore.getFireAt() == null);
    } finally { saved.restore(); }
    return true;
}

(:test)
function oneOffDismissalRestoresDailyAlarm(logger as Logger) as Boolean {
    var saved = new SavedAlarm();
    try {
        AlarmStore.setTime(7, 15);
        AlarmStore.setEnabled(true);
        AlarmStore.scheduleTest(300);
        Storage.setValue("fireAt", Time.now().value() - 1);
        Test.assert(AlarmStore.isRinging());
        AlarmStore.dismiss();
        Test.assert(AlarmStore.isEnabled());
        Test.assert(!AlarmStore.isTestPending());
        Test.assert(!AlarmStore.isRinging());
        Test.assertEqual(AlarmStore.getHour(), 7);
        Test.assertEqual(AlarmStore.getMinute(), 15);
        Test.assert((AlarmStore.getFireAt() as Number) > Time.now().value());
    } finally { saved.restore(); }
    return true;
}

(:test)
function sideloadDeadlineIsAppliedOnlyOnce(logger as Logger) as Boolean {
    var saved = new SavedAlarm();
    var property = Properties.getValue("SideloadTestAt");
    try {
        AlarmStore.setEnabled(false);
        Storage.deleteValue("sideloadTestApplied");
        Properties.setValue("SideloadTestAt", Time.now().value() + 600);
        AlarmStore.applySideloadTest();
        Test.assert(AlarmStore.isTestPending());
        AlarmStore.dismiss();
        AlarmStore.applySideloadTest();
        Test.assert(!AlarmStore.isTestPending());
        Test.assert(AlarmStore.getFireAt() == null);
        Properties.setValue("SideloadTestAt", Time.now().value() - 60);
        AlarmStore.applySideloadTest();
        Test.assert(!AlarmStore.isTestPending());
    } finally {
        Properties.setValue("SideloadTestAt", property);
        saved.restore();
    }
    return true;
}
