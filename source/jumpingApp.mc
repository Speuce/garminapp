// ABOUTME: Entry point for the jumping jack app, which records raw accelerometer data.
// ABOUTME: Owns the AccelerometerLogger and makes sure recording stops when the app exits.
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class jumpingApp extends Application.AppBase {

    private var _logger as AccelerometerLogger = new AccelerometerLogger();

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        _logger.stop();
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new jumpingView(_logger.recording()), new jumpingDelegate(_logger) ];
    }

}

function getApp() as jumpingApp {
    return Application.getApp() as jumpingApp;
}