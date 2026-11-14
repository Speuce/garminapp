// ABOUTME: Streams accelerometer samples from the watch sensor into a Recording and prints each log line.
// ABOUTME: On a sideloaded app, printed lines land in GARMIN/APPS/LOGS/<APPNAME>.TXT when that file exists.
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.WatchUi;

class AccelerometerLogger {

    private const SAMPLE_RATE = 25;

    private var _recording as Recording = new Recording(SAMPLE_RATE);

    function initialize() {
    }

    function recording() as Recording {
        return _recording;
    }

    function toggle() as Void {
        if (_recording.isRecording()) {
            stop();
        } else {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => SAMPLE_RATE
                }
            });
            System.println(_recording.start());
            buzz(300);
        }
        WatchUi.requestUpdate();
    }

    function stop() as Void {
        if (!_recording.isRecording()) {
            return;
        }
        Sensor.unregisterSensorDataListener();
        System.println(_recording.stop());
        buzz(300);
    }

    function mark() as Void {
        System.println(_recording.marker());
        buzz(100);
        WatchUi.requestUpdate();
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null || !_recording.isRecording()) {
            return;
        }
        var lines = _recording.samples(accel.x, accel.y, accel.z);
        for (var i = 0; i < lines.size(); i++) {
            System.println(lines[i]);
        }
        WatchUi.requestUpdate();
    }

    // Buzzes so a button press can be confirmed mid-exercise without looking at the screen.
    private function buzz(milliseconds as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, milliseconds)]);
        }
    }

}
