import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

// The app class is loaded by both the foreground app and the background process.
(:background)
class JumpStartApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var store = new AlarmStore(new DeviceAlarmStorage(), AlarmStore.STORAGE_KEY);
        var controller = new AlarmController(store);
        // Launched from the "Alarm!" wake prompt (or manually while ringing)
        if (AlarmStore.isRinging()) {
            return [new RingView(), new RingDelegate()];
        }

        return [new TrailView(controller), new TrailDelegate(controller)];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new AlarmService()];
    }
}

function getApp() as JumpStartApp {
    return Application.getApp() as JumpStartApp;
}
