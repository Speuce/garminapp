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
        _controller.select();
        WatchUi.requestUpdate();
        return true;
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
