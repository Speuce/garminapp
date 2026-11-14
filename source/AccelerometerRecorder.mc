// ABOUTME: Records a training activity whose FIT file includes the raw accelerometer stream via SensorLogging.
// ABOUTME: Markers become FIT laps; the saved file lands in GARMIN/ACTIVITY and syncs to Garmin Connect.
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.SensorLogging;
import Toybox.Timer;
import Toybox.WatchUi;

class AccelerometerRecorder {

    private var _session as ActivityRecording.Session?;
    private var _sensorLogger as SensorLogging.SensorLogger?;
    private var _screenRefresh as Timer.Timer = new Timer.Timer();
    private var _markerCount as Number = 0;

    function initialize() {
    }

    function isRecording() as Boolean {
        return _session != null;
    }

    function markerCount() as Number {
        return _markerCount;
    }

    function sampleCount() as Number {
        var stats = _sensorLogger != null ? _sensorLogger.getStats() : null;
        return stats != null ? stats.sampleCount : 0;
    }

    function toggle() as Void {
        if (isRecording()) {
            stop();
        } else {
            start();
        }
        WatchUi.requestUpdate();
    }

    function stop() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        session.stop();
        session.save();
        _session = null;
        _screenRefresh.stop();
        buzz(300);
    }

    function mark() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        session.addLap();
        _markerCount++;
        buzz(100);
        WatchUi.requestUpdate();
    }

    function refreshScreen() as Void {
        WatchUi.requestUpdate();
    }

    private function start() as Void {
        var sensorLogger = new SensorLogging.SensorLogger({:accelerometer => {:enabled => true}});
        var session = ActivityRecording.createSession({
            :name => "Jumping jacks",
            :sport => Activity.SPORT_TRAINING,
            :subSport => Activity.SUB_SPORT_CARDIO_TRAINING,
            :sensorLogger => sensorLogger
        });
        session.start();
        _sensorLogger = sensorLogger;
        _session = session;
        _markerCount = 0;
        _screenRefresh.start(method(:refreshScreen), 1000, true);
        buzz(300);
    }

    // Buzzes so a button press can be confirmed mid-exercise without looking at the screen.
    private function buzz(milliseconds as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, milliseconds)]);
        }
    }

}
