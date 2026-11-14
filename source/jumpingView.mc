// ABOUTME: Main screen showing whether recording is on, samples captured, and markers dropped.
// ABOUTME: The sample count rising each second confirms the accelerometer is delivering data.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class jumpingView extends WatchUi.View {

    private var _recorder as AccelerometerRecorder;

    function initialize(recorder as AccelerometerRecorder) {
        View.initialize();
        _recorder = recorder;
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var x = dc.getWidth() / 2;
        var y = dc.getHeight() / 2;
        var lineHeight = dc.getFontHeight(Graphics.FONT_SMALL);
        var lines = _recorder.isRecording()
            ? ["REC", "Samples " + _recorder.sampleCount(), "Marks " + _recorder.markerCount(), "BACK: mark"]
            : ["Ready", "START: record"];
        var top = y - lines.size() * lineHeight / 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(x, top + i * lineHeight, Graphics.FONT_SMALL, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

}
