// ABOUTME: Entry point for the jumping jack app, which records raw accelerometer data into a FIT activity.
// ABOUTME: Owns the AccelerometerRecorder and makes sure the activity is saved when the app exits.
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class jumpingApp extends Application.AppBase {

    private var _recorder as AccelerometerRecorder = new AccelerometerRecorder();

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        _recorder.stop();
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new jumpingView(_recorder), new jumpingDelegate(_recorder) ];
    }

}

function getApp() as jumpingApp {
    return Application.getApp() as jumpingApp;
}