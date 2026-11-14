// import Toybox.Graphics;
// import Toybox.Lang;
// import Toybox.System;
// import Toybox.Time;
// import Toybox.Time.Gregorian;
// import Toybox.Timer;
// import Toybox.WatchUi;

// class MainView extends WatchUi.View {

//     private var _timer as Timer.Timer?;

//     function initialize() {
//         View.initialize();
//     }

//     function onShow() as Void {
//         _timer = new Timer.Timer();
//         _timer.start(method(:onTick), 1000, true);
//     }

//     function onHide() as Void {
//         if (_timer != null) {
//             _timer.stop();
//             _timer = null;
//         }
//     }

//     function onTick() as Void {
//         // If the alarm time arrives while the app is open, start ringing.
//         if (AlarmStore.isRinging()) {
//             WatchUi.switchToView(new RingView(), new RingDelegate(), WatchUi.SLIDE_IMMEDIATE);
//             return;
//         }
//         WatchUi.requestUpdate();
//     }

//     function onUpdate(dc as Dc) as Void {
//         var w = dc.getWidth();
//         var h = dc.getHeight();
//         dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
//         dc.clear();

//         var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
//         dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
//         dc.drawText(w / 2, h * 0.14, Graphics.FONT_SMALL,
//             "Now " + AlarmStore.formatTime(now.hour, now.min),
//             Graphics.TEXT_JUSTIFY_CENTER);

//         var on = AlarmStore.isEnabled();
//         dc.setColor(on ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
//         dc.drawText(w / 2, h * 0.30, Graphics.FONT_NUMBER_HOT,
//             AlarmStore.formatTime(AlarmStore.getHour(), AlarmStore.getMinute()),
//             Graphics.TEXT_JUSTIFY_CENTER);

//         dc.setColor(on ? Graphics.COLOR_GREEN : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
//         dc.drawText(w / 2, h * 0.62, Graphics.FONT_MEDIUM,
//             on ? "ALARM ON" : "ALARM OFF",
//             Graphics.TEXT_JUSTIFY_CENTER);

//         // Show when the background event is actually scheduled (for debugging)
//         var fireAt = AlarmStore.getFireAt();
//         var sched = "Not scheduled";
//         if (on && fireAt != null) {
//             var f = Gregorian.info(new Time.Moment(fireAt), Time.FORMAT_SHORT);
//             sched = "Fires " + f.day.format("%02d") + "/" + f.month.format("%02d") + " "
//                 + AlarmStore.formatTime(f.hour, f.min);
//         }
//         dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
//         dc.drawText(w / 2, h * 0.76, Graphics.FONT_XTINY, sched, Graphics.TEXT_JUSTIFY_CENTER);

//         dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
//         dc.drawText(w / 2, h * 0.86, Graphics.FONT_XTINY, "START = menu", Graphics.TEXT_JUSTIFY_CENTER);
//     }
// }

// class MainDelegate extends WatchUi.BehaviorDelegate {

//     function initialize() {
//         BehaviorDelegate.initialize();
//     }

//     function onSelect() as Boolean {
//         openMenu();
//         return true;
//     }

//     function onTap(evt as WatchUi.ClickEvent) as Boolean {
//         openMenu();
//         return true;
//     }

//     private function openMenu() as Void {
//         var menu = new WatchUi.Menu2({:title => "Alarm"});
//         menu.addItem(new WatchUi.ToggleMenuItem("Enabled", null, :toggle,
//             AlarmStore.isEnabled(), null));
//         menu.addItem(new WatchUi.MenuItem("Set time",
//             AlarmStore.formatTime(AlarmStore.getHour(), AlarmStore.getMinute()),
//             :setTime, null));
//         menu.addItem(new WatchUi.MenuItem("Test ring", "Ring screen now", :testRing, null));
//         WatchUi.pushView(menu, new AlarmMenuDelegate(), WatchUi.SLIDE_LEFT);
//     }
// }

// class AlarmMenuDelegate extends WatchUi.Menu2InputDelegate {

//     function initialize() {
//         Menu2InputDelegate.initialize();
//     }

//     function onSelect(item as WatchUi.MenuItem) as Void {
//         var id = item.getId();
//         if (id == :toggle) {
//             AlarmStore.setEnabled((item as WatchUi.ToggleMenuItem).isEnabled());
//         } else if (id == :setTime) {
//             WatchUi.pushView(new TimePickerView(), new TimePickerDelegate(), WatchUi.SLIDE_LEFT);
//         } else if (id == :testRing) {
//             WatchUi.pushView(new RingView(), new RingDelegate(), WatchUi.SLIDE_LEFT);
//         }
//     }

//     function onBack() as Void {
//         WatchUi.popView(WatchUi.SLIDE_RIGHT);
//     }
// }
