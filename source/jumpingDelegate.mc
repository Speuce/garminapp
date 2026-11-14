// ABOUTME: Button handling: START/STOP toggles recording, BACK adds a lap marker while recording.
// ABOUTME: BACK exits the app as usual when not recording.
import Toybox.Lang;
import Toybox.WatchUi;

class jumpingDelegate extends WatchUi.BehaviorDelegate {

    private var _recorder as AccelerometerRecorder;

    function initialize(recorder as AccelerometerRecorder) {
        BehaviorDelegate.initialize();
        _recorder = recorder;
    }

    function onSelect() as Boolean {
        _recorder.toggle();
        return true;
    }

    function onBack() as Boolean {
        if (!_recorder.isRecording()) {
            return false;
        }
        _recorder.mark();
        return true;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new jumpingMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}