import Toybox.Lang;
import Toybox.Test;

(:test)
class FakeHeartRateSource extends HeartRateSource {
    var available = true;
    var value as Number? = null;
    var starts = 0;
    var stops = 0;
    var reads = 0;
    var failRead = false;
    function initialize() { HeartRateSource.initialize(); }
    function enable() as Boolean { starts++; return available; }
    function disable() as Void { stops++; }
    function read() as Number? {
        reads++;
        if (failRead) { throw new Lang.InvalidValueException("Sensor unavailable"); }
        return value;
    }
}

(:test)
function heartRateUsesCurrentSamplesAndStopsWithView(logger as Logger) as Boolean {
    var source = new FakeHeartRateSource();
    var monitor = new HeartRateMonitor(source);
    Test.assert(monitor.current() == null);
    Test.assertEqual(source.reads, 0);
    monitor.start(); monitor.start();
    Test.assertEqual(source.starts, 1);
    source.value = 62; Test.assertEqual(monitor.current(), 62);
    source.value = 103; Test.assertEqual(monitor.current(), 103);
    source.value = null; Test.assert(monitor.current() == null);
    source.value = 0; Test.assert(monitor.current() == null);
    source.value = 70;
    monitor.stop(); monitor.stop();
    Test.assertEqual(source.stops, 1);
    var reads = source.reads;
    Test.assert(monitor.current() == null);
    Test.assertEqual(source.reads, reads);
    monitor.start();
    Test.assertEqual(monitor.current(), 70);
    monitor.stop();
    Test.assertEqual(source.starts, 2);
    Test.assertEqual(source.stops, 2);
    return true;
}

(:test)
function missingHeartRateRecoversAfterSensorFailure(logger as Logger) as Boolean {
    var source = new FakeHeartRateSource();
    source.available = false;
    var monitor = new HeartRateMonitor(source);
    monitor.start();
    Test.assert(monitor.current() == null);
    Test.assertEqual(source.reads, 1);
    source.value = 74;
    Test.assertEqual(monitor.current(), 74); // Already-enabled system sensor.
    monitor.stop();
    Test.assertEqual(source.stops, 0);
    source.available = true;
    monitor.start();
    source.failRead = true;
    Test.assert(monitor.current() == null);
    source.failRead = false;
    source.value = 80;
    Test.assertEqual(monitor.current(), 80);
    monitor.stop();
    Test.assertEqual(source.stops, 1);
    return true;
}
