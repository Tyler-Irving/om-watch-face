using Toybox.Application;
using Toybox.Background;
using Toybox.Time;
using Toybox.WatchUi;

//
// OleMissWatchFaceApp.mc — the AppBase entry point declared in manifest.xml
// (`entry="OleMissWatchFaceApp"`). Connect IQ instantiates this class once
// when the watch face is launched; getInitialView() returns the View that
// owns all the drawing logic.
//
// As of v0.2 this app also wires a background service (BackgroundService) to
// keep the schedule live. The OS asks for the delegate via getServiceDelegate
// when a registered temporal event matures, and the delegate hands data back
// via Storage + onBackgroundData.
//
class OleMissWatchFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //
    // Lifecycle hook. We use this to ensure a temporal event is registered on
    // first launch so the background service starts on its own. Re-launches
    // and resumes don't replace an already-registered event.
    //
    function onStart(state) {
        if (Background.getTemporalEventRegisteredTime() == null) {
            // First-launch kick: schedule the very first poll for `MIN_INTERVAL_SEC`
            // from now (BackgroundService's clamp would force this anyway). After
            // that fires, BackgroundService.onResponse re-registers itself based
            // on the freshly-fetched schedule.
            var firstWake = Time.now().add(new Time.Duration(5 * 60));
            Background.registerForTemporalEvent(firstWake);
        }
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
    // Called by the OS when a registered temporal event matures. We hand
    // back a fresh service delegate; the OS instantiates a separate process
    // (the "background process") and runs onTemporalEvent on this delegate.
    //
    function getServiceDelegate() {
        return [new BackgroundService()];
    }

    //
    // Bridge from background → foreground. Called when the background
    // process exits via Background.exit(). Storage already holds the new
    // schedule by this point — we just need to invalidate Schedule's
    // in-memory cache and request a redraw so the view picks it up.
    //
    function onBackgroundData(data) {
        Schedule.invalidateCache();
        WatchUi.requestUpdate();
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
