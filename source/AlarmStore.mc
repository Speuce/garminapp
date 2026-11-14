import Toybox.Application.Storage;
import Toybox.Application.Properties;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;

// Persistent alarm settings + scheduling helpers.
module AlarmStore {

    const RING_WINDOW_SEC = 600;   // alarm counts as "ringing" for 10 min
    const SNOOZE_SEC = 540;        // 9 minutes (must be >= 5 min for temporal events)

    function getHour() as Number {
        var v = Storage.getValue("hour");
        return (v instanceof Number) ? v : 7;
    }

    function getMinute() as Number {
        var v = Storage.getValue("minute");
        return (v instanceof Number) ? v : 0;
    }

    function isEnabled() as Boolean {
        var v = Storage.getValue("enabled");
        return (v instanceof Boolean) ? v : false;
    }

    function setTime(hour as Number, minute as Number) as Void {
        Storage.deleteValue("testAlarm");
        Storage.setValue("hour", hour);
        Storage.setValue("minute", minute);
        reschedule();
    }

    function setEnabled(on as Boolean) as Void {
        Storage.deleteValue("testAlarm");
        Storage.setValue("enabled", on);
        reschedule();
    }

    // Next occurrence of the configured time (local time), strictly in the future.
    function nextMoment() as Moment {
        var offset = new Time.Duration(getHour() * 3600 + getMinute() * 60);
        var m = Time.today().add(offset);          // Time.today() = local midnight
        if (m.value() <= Time.now().value() + 60) {
            m = m.add(new Time.Duration(86400));
        }
        return m;
    }

    function getFireAt() as Number or Null {
        var v = Storage.getValue("fireAt");
        return (v instanceof Number) ? v : null;
    }

    function schedule(m as Moment) as Void {
        Storage.setValue("fireAt", m.value());
        try {
            Background.registerForTemporalEvent(m);
        } catch (e) {
            // Ignore: the alarm will be re-registered next time the app opens.
        }
    }

    function isTestPending() as Boolean {
        var value = Storage.getValue("testAlarm");
        return value instanceof Boolean ? value : false;
    }

    // One-off hardware test; daily alarm settings are preserved.
    function scheduleTest(seconds as Number) as Void {
        Storage.setValue("testAlarm", true);
        schedule(Time.now().add(new Time.Duration(seconds)));
    }

    // Optional build-time deadline for sideloading. Each deadline is applied
    // once, so reopening the app after dismissal cannot restart the test.
    function applySideloadTest() as Void {
        var deadline = Properties.getValue("SideloadTestAt");
        if (!(deadline instanceof Number) || deadline <= Time.now().value()) { return; }
        var applied = Storage.getValue("sideloadTestApplied");
        if (applied instanceof Number && applied == deadline) { return; }
        scheduleTest(deadline - Time.now().value());
        Storage.setValue("sideloadTestApplied", deadline);
    }

    function reschedule() as Void {
        if (!isEnabled()) {
            Background.deleteTemporalEvent();
            Storage.deleteValue("fireAt");
            return;
        }
        schedule(nextMoment());
    }

    function isRinging() as Boolean {
        var fireAt = getFireAt();
        if ((!isEnabled() && !isTestPending()) || fireAt == null) {
            return false;
        }
        var now = Time.now().value();
        return now >= fireAt && now < fireAt + RING_WINDOW_SEC;
    }

    function dismiss() as Void {
        Storage.deleteValue("testAlarm");
        reschedule();   // next day's occurrence
    }

    function snooze() as Void {
        schedule(Time.now().add(new Time.Duration(SNOOZE_SEC)));
    }

    function formatTime(hour as Number, minute as Number) as String {
        return hour.format("%02d") + ":" + minute.format("%02d");
    }
}
