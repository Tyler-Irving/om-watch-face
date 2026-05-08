using Toybox.Application;
using Toybox.WatchUi;

//
// OleMissWatchFaceApp.mc — the AppBase entry point declared in manifest.xml
// (`entry="OleMissWatchFaceApp"`). Connect IQ instantiates this class once
// when the watch face is launched; getInitialView() returns the View that
// owns all the drawing logic.
//
class OleMissWatchFaceApp extends Application.AppBase {

    function initialize() {
        // In Monkey C, subclasses must explicitly initialize their parent.
        // The parent's initialize() is called via the unqualified class name.
        AppBase.initialize();
    }

    // Lifecycle hooks — useful later for waking a background service or
    // restoring cached schedule data. No-ops for the offline v0.
    function onStart(state) {
    }

    function onStop(state) {
    }

    //
    // Connect IQ calls this on launch and expects an Array whose first
    // element is the initial WatchUi.View. For watch faces, the View must
    // extend WatchUi.WatchFace (see OleMissWatchFaceView.mc).
    //
    function getInitialView() {
        return [new OleMissWatchFaceView()];
    }

    //
    // Fired when the user changes a setting in Garmin Connect Mobile.
    // Request a redraw so the view picks up the new value (e.g. the
    // 12/24-hour toggle takes effect without leaving the watch face).
    //
    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}
