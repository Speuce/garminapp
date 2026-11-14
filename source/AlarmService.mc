import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

// Runs in the background process when the temporal event fires.
// It asks the system to wake the app, which shows the "Alarm!" prompt
// and vibrates the watch; accepting it launches the ringing screen.
(:background)
class AlarmService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        Background.requestApplicationWake("Alarm! Tap to open");
        Background.exit(null);
    }
}
