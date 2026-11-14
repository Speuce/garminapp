// ABOUTME: Records a training activity whose FIT file includes the raw accelerometer stream via SensorLogging,
// ABOUTME: while counting reps live from the same sensor. Markers become FIT laps; the FIT syncs to Garmin Connect.
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.SensorLogging;
import Toybox.WatchUi;

class AccelerometerRecorder {

    private var _session as ActivityRecording.Session?;
    private var _sensorLogger as SensorLogging.SensorLogger?;
    private var _repCounter as RepCounter = new RepCounter();
    private var _markerCount as Number = 0;

    function initialize() {
    }

    function isRecording() as Boolean {
        return _session != null;
    }

    function markerCount() as Number {
        return _markerCount;
    }

    function repCount() as Number {
        return _repCounter.count();
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
        Sensor.unregisterSensorDataListener();
        _session = null;
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

    function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var y = accel.y;
        for (var i = 0; i < y.size(); i++) {
            _repCounter.add(y[i]);
        }
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
        _repCounter = new RepCounter();
        Sensor.registerSensorDataListener(method(:onSensorData), {
            :period => 1,
            :accelerometer => {:enabled => true, :sampleRate => 25}
        });
        buzz(300);
    }

    // Buzzes so a button press can be confirmed mid-exercise without looking at the screen.
    private function buzz(milliseconds as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, milliseconds)]);
        }
    }

}
