// ABOUTME: Button handling: START/STOP toggles recording, BACK drops a marker while recording.
// ABOUTME: BACK exits the app as usual when not recording.
import Toybox.Lang;
import Toybox.WatchUi;

class jumpingDelegate extends WatchUi.BehaviorDelegate {

    private var _logger as AccelerometerLogger;

    function initialize(logger as AccelerometerLogger) {
        BehaviorDelegate.initialize();
        _logger = logger;
    }

    function onSelect() as Boolean {
        _logger.toggle();
        return true;
    }

    function onBack() as Boolean {
        if (!_logger.recording().isRecording()) {
            return false;
        }
        _logger.mark();
        return true;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new jumpingMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}