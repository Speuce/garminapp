import Toybox.Lang;
import Toybox.WatchUi;

class jumpingDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new jumpingMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}