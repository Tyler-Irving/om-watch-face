using Toybox.Application;
using Toybox.Time;
using Toybox.Lang;

//
// ScheduleStore.mc — thin facade over Application.Storage for the data the
// background service produces and the foreground watch face consumes.
//
// Storage is shared between the background and foreground processes, so this
// module is the single source of truth for both keys *and* serialized shape.
// Time.Moment isn't directly storable, so kickoff times round-trip as Number
// epoch seconds (`:kickoffSec`); Schedule.mc rehydrates them on read.
//
module ScheduleStore {

    // Storage keys. Kept as constants so a typo can't desync producer/consumer.
    const KEY_GAMES      = "games";
    const KEY_LAST_FETCH = "lastFetchSec";
    const KEY_LAST_ERROR = "lastError";
    const KEY_POLL_MODE  = "pollMode";

    // Poll-mode tags written by BackgroundService for diagnostic / UI purposes.
    // The view doesn't strictly need these — the schedule itself implies state —
    // but exposing the mode makes it easy to surface "live updating…" copy or
    // a stale-data indicator later.
    const POLL_MODE_DAILY = 0;
    const POLL_MODE_LIVE  = 1;

    //
    // Persist a freshly-fetched array of games and clear any prior error.
    // Each entry is the storage shape:
    //   :opponent   String
    //   :home       Boolean
    //   :kickoffSec Number   (epoch seconds, UTC)
    //   :confirmed  Boolean
    //   :status     String   (raw provider status, e.g. "STATUS_SCHEDULED")
    //
    function saveGames(games as Lang.Array<Lang.Dictionary>) {
        Application.Storage.setValue(KEY_GAMES, games);
        Application.Storage.setValue(KEY_LAST_FETCH, Time.now().value());
        Application.Storage.deleteValue(KEY_LAST_ERROR);
    }

    function loadGames() as Lang.Array<Lang.Dictionary> or Null {
        return Application.Storage.getValue(KEY_GAMES);
    }

    function setError(msg as Lang.String) {
        Application.Storage.setValue(KEY_LAST_ERROR, msg);
    }

    function getLastError() as Lang.String or Null {
        return Application.Storage.getValue(KEY_LAST_ERROR);
    }

    function getLastFetchSec() as Lang.Number or Null {
        return Application.Storage.getValue(KEY_LAST_FETCH);
    }

    function setPollMode(mode as Lang.Number) {
        Application.Storage.setValue(KEY_POLL_MODE, mode);
    }

    function getPollMode() as Lang.Number {
        var v = Application.Storage.getValue(KEY_POLL_MODE);
        return (v != null) ? v : POLL_MODE_DAILY;
    }
}
