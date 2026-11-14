import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Application.Storage;
import Toybox.Time;

// Runs in the background process when the temporal event fires.
// It asks the system to wake the app, which shows the "Alarm!" prompt
// and vibrates the watch; accepting it launches the ringing screen.
(:background)
class AlarmService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var now = Time.now().value();
        System.println("Alarm background wake (UTC): " + now);
        var at = Storage.getValue("jumpstart.wakeAt");
        var state = Storage.getValue("jumpstart.schedule.v1");
        // Keep the current occurrence available for a launch from the prompt.
        if (state instanceof Dictionary && (at instanceof Number || at instanceof Long)) {
            state["fireAt"] = at.toNumber();
            Storage.setValue("jumpstart.schedule.v1", state);
        }
        // Continue recurring alarms even when the user ignores a wake prompt.
        var snapshot = Storage.getValue("jumpstart.alarms.v1");
        var next = null;
        if (snapshot instanceof Dictionary && snapshot["alarms"] instanceof Array) {
            var records = snapshot["alarms"] as Array<Dictionary>;
            for (var i = 0; i < records.size(); i++) {
                if (!AlarmData.valid(records[i])) { continue; }
                var candidate = AlarmSchedule.next(records[i], now);
                if (candidate != null && (next == null || candidate < next)) { next = candidate; }
            }
        }
        if (state instanceof Dictionary) {
            var test = state["testAt"];
            if ((test instanceof Number || test instanceof Long) && test > now && (next == null || test < next)) {
                next = test.toNumber();
            }
        }
        if (next != null) {
            Storage.setValue("jumpstart.wakeAt", next);
            // Connect IQ requires at least five minutes between background runs.
            try {
                Background.registerForTemporalEvent(new Time.Moment(next < now + 300 ? now + 300 : next));
            } catch (e) { System.println("Next wake registration: " + e.getErrorMessage()); }
        } else { Storage.deleteValue("jumpstart.wakeAt"); }
        Background.requestApplicationWake("Alarm! Tap to open");
        Background.exit(null);
    }
}
