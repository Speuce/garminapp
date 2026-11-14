import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

(:background)
class JumpStartApp extends Application.AppBase {
    private var _controller;
    private var _scheduler;
    private var _timer;
    private var _ringing as Boolean = false;

    function initialize() { AppBase.initialize(); }

    (:typecheck(disableBackgroundCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var storage = new DeviceAlarmStorage();
        var store = new AlarmStore(storage, AlarmStore.STORAGE_KEY);
        // Import an enabled alarm from the earlier single-alarm build once.
        if (Storage.getValue("jumpstart.migrated") != true && store.readable) {
            if (store.records.size() == 0 && Storage.getValue("enabled") == true) {
                var item = AlarmData.create();
                var hour = Storage.getValue("hour");
                var minute = Storage.getValue("minute");
                item["hour"] = hour instanceof Number ? hour : 7;
                item["minute"] = minute instanceof Number ? minute : 0;
                item["days"] = 127;
                if (store.save(item)) { Storage.setValue("jumpstart.migrated", true); }
            } else { Storage.setValue("jumpstart.migrated", true); }
        }
        _controller = new AlarmController(store);
        _scheduler = new AlarmScheduler(store, storage, Time.now().value());
        _scheduler.applySideload(Properties.getValue("SideloadTestAt"), Time.now().value());
        showTestTime();
        registerWake();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        if (_scheduler.due(Time.now().value())) {
            _ringing = true;
            return [new RingView(false), new RingDelegate()];
        }
        return [new TrailView(_controller), new TrailDelegate(_controller)];
    }

    (:typecheck(disableBackgroundCheck))
    function registerWake() as Void {
        try {
            var at = _scheduler.fireAt;
            if (at == null) { Background.deleteTemporalEvent(); Storage.deleteValue("jumpstart.wakeAt"); }
            else if (at > Time.now().value()) {
                Storage.setValue("jumpstart.wakeAt", at);
                Background.registerForTemporalEvent(new Time.Moment(at));
                System.println("Alarm scheduled (UTC): " + at);
            }
        } catch (e) {
            _controller.notice = "Keep app open";
            System.println("Alarm wake registration: " + e.getErrorMessage());
        }
    }

    (:typecheck(disableBackgroundCheck))
    function changed() as Void {
        if (_scheduler.refresh(Time.now().value())) { registerWake(); }
        var command = _controller.command;
        _controller.command = 0;
        if (command == 1) { showRing(true); }
        else if (command == 300) {
            _scheduler.armTest(Time.now().value() + 300, Time.now().value());
            showTestTime();
            registerWake();
        }
    }

    (:typecheck(disableBackgroundCheck))
    function showTestTime() as Void {
        if (_scheduler.testAt != null && _scheduler.testAt > Time.now().value()) {
            var info = Gregorian.info(new Time.Moment(_scheduler.testAt), Time.FORMAT_SHORT);
            _controller.notice = "Test " + info.hour.format("%02d") + ":" + info.min.format("%02d");
        }
    }

    (:typecheck(disableBackgroundCheck))
    function onTick() as Void {
        if (_ringing) { return; }
        if (_scheduler.refresh(Time.now().value())) { registerWake(); }
        if (_scheduler.due(Time.now().value())) { showRing(false); }
    }

    (:typecheck(disableBackgroundCheck))
    function showRing(preview as Boolean) as Void {
        _ringing = true;
        WatchUi.switchToView(new RingView(preview), new RingDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    (:typecheck(disableBackgroundCheck))
    function finishRing(preview as Boolean) as Void {
        if (!preview) { _scheduler.dismiss(Time.now().value()); registerWake(); }
        _ringing = false;
        WatchUi.switchToView(new TrailView(_controller), new TrailDelegate(_controller), WatchUi.SLIDE_IMMEDIATE);
    }

    (:typecheck(disableBackgroundCheck))
    function onStop(state as Dictionary?) as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
        if (_scheduler != null && !_ringing && _scheduler.refresh(Time.now().value())) { registerWake(); }
    }

    function getServiceDelegate() as [System.ServiceDelegate] { return [new AlarmService()]; }
}

function getApp() as JumpStartApp { return Application.getApp() as JumpStartApp; }
