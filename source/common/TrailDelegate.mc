import Toybox.WatchUi;
import Toybox.Lang;

class TrailDelegate extends WatchUi.BehaviorDelegate {
    private var _controller as AlarmController;

    function initialize(controller as AlarmController) {
        BehaviorDelegate.initialize();
        _controller = controller;
    }

    function onPreviousPage() as Boolean {
        _controller.move(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _controller.move(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        // On the list, inspect the raw input so a moon tap does not edit an alarm.
        if (_controller.state == AlarmController.LIST) { return false; }
        return selectCurrent();
    }

    private function selectCurrent() as Boolean {
        _controller.select();
        getApp().changed();
        WatchUi.requestUpdate();
        return true;
    }

    // Some devices expose LIGHT to apps; others reserve it in firmware.
    // Only use it on the main screen so an editor draft remains untouched.
    function onKey(event as WatchUi.KeyEvent) as Boolean {
        if (event.getKey() == WatchUi.KEY_ENTER) { return selectCurrent(); }
        if (event.getKey() == WatchUi.KEY_LIGHT && _controller.state == AlarmController.LIST) {
            _controller.selection = AlarmController.SLEEP_SELECTION;
            return selectCurrent();
        }
        return false;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        var point = event.getCoordinates();
        if ((WatchUi.getCurrentView()[0] as TrailView).hitSleep(point[0], point[1])) {
            _controller.selection = AlarmController.SLEEP_SELECTION;
        }
        return selectCurrent();
    }

    function onMenu() as Boolean {
        _controller.menu();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        if (!_controller.back()) { WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); }
        else { WatchUi.requestUpdate(); }
        return true;
    }
}
