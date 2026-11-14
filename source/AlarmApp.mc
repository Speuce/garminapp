import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The app class is loaded by both the foreground app and the background process.
(:background)
class AlarmApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Launched from the "Alarm!" wake prompt (or manually while ringing)
        if (AlarmStore.isRinging()) {
            return [new RingView(), new RingDelegate()];
        }
        return [new MainView(), new MainDelegate()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new AlarmService()];
    }
}

function getApp() as AlarmApp {
    return Application.getApp() as AlarmApp;
}
