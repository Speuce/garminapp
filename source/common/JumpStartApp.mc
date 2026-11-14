import Toybox.Application;
import Toybox.WatchUi;

class JumpStartApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var store = new AlarmStore(new DeviceAlarmStorage(), AlarmStore.STORAGE_KEY);
        var controller = new AlarmController(store);
        return [new TrailView(controller), new TrailDelegate(controller)];
    }
}
