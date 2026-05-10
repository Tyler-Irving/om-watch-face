using Toybox.Time;
using Toybox.Lang;

//
// Schedule.mc — read-only view over the schedule data BackgroundService
// persists into Storage. Provides "next game" lookup and status
// classification for the watch face's countdown strip.
//
// In Monkey C, a `module` is roughly a namespace — module-level functions
// and constants are reached as Schedule.foo() / Schedule.STATUS_LIVE.
//
module Schedule {

    // ----- Game status enum --------------------------------------------------
    // Monkey C does not have a real enum keyword; the convention is module
    // constants. These values are returned from getGameStatus() and consumed
    // by the view to decide what to render in the countdown line.
    const STATUS_UPCOMING = 0;  // kickoff is in the future
    const STATUS_LIVE     = 1;  // game is currently in progress
    const STATUS_FINAL    = 2;  // game ended within the FINAL display window
    const STATUS_PAST     = 3;  // older than the FINAL window — show the next one

    // ----- Status window constants ------------------------------------------
    // "LIVE" is shown for ASSUMED_GAME_LENGTH_SEC after kickoff. After that,
    // "FINAL" is shown until FINAL_WINDOW_END_SEC has elapsed since kickoff.
    // Tweak these if you'd rather mirror the actual game clock from a feed.
    const ASSUMED_GAME_LENGTH_SEC = 4 * 3600;   // 4h: covers most college games
    const FINAL_WINDOW_END_SEC    = 12 * 3600;  // FINAL fades 12h after kickoff

    // The view considers a game "next" only if it is within this window.
    // Outside the window, it falls back to the "Hotty Toddy" filler.
    const LOOKAHEAD_WINDOW_SEC = 14 * 24 * 3600; // 14 days

    // Cached hydrated schedule. Rebuilt lazily on getSchedule() after
    // invalidateCache() — which the App calls when onBackgroundData fires.
    var _cachedSchedule = null;

    //
    // Returns the full schedule as an Array of Dictionary entries, each:
    //   :opponent  → String, e.g. "Alabama"
    //   :home      → Boolean, true for home (renders "vs"), false for away ("@")
    //   :kickoff   → Time.Moment, kickoff in UTC
    //   :confirmed → Boolean, false → render "TBD" instead of a countdown
    //
    // Sourced from Storage (background-fetched). Returns an empty array
    // before the first successful background fetch lands or when the
    // upstream returns no events (off-season).
    //
    function getSchedule() as Lang.Array<Lang.Dictionary> {
        if (_cachedSchedule == null) {
            _cachedSchedule = _loadSchedule();
        }
        return _cachedSchedule;
    }

    //
    // Drops the in-memory cache so the next getSchedule() re-reads from
    // Storage. Called by the App after onBackgroundData fires.
    //
    function invalidateCache() {
        _cachedSchedule = null;
    }

    //
    // Returns the soonest game that is either currently LIVE / FINAL or whose
    // kickoff is upcoming and within LOOKAHEAD_WINDOW_SEC. Returns null if
    // there is no game to show — the view renders "Hotty Toddy" in that case.
    //
    function getNextGame() as Lang.Dictionary or Null {
        var games = getSchedule();
        var nowSec = Time.now().value();

        var liveOrFinal = null;
        var nextUpcoming = null;
        var nextUpcomingKickoff = 0;

        for (var i = 0; i < games.size(); i++) {
            var game = games[i];
            var status = getGameStatus(game);

            if (status == STATUS_LIVE || status == STATUS_FINAL) {
                // Prefer a currently-airing game over any future one.
                liveOrFinal = game;
                break;
            }

            if (status == STATUS_UPCOMING) {
                var kickoffSec = game[:kickoff].value();
                var deltaSec   = kickoffSec - nowSec;
                if (deltaSec <= LOOKAHEAD_WINDOW_SEC) {
                    if (nextUpcoming == null || kickoffSec < nextUpcomingKickoff) {
                        nextUpcoming = game;
                        nextUpcomingKickoff = kickoffSec;
                    }
                }
            }
        }

        if (liveOrFinal != null) {
            return liveOrFinal;
        }
        return nextUpcoming;
    }

    //
    // Classifies a single game relative to Time.now(). See STATUS_* above.
    //
    function getGameStatus(game as Lang.Dictionary) as Lang.Number {
        var elapsed = Time.now().value() - game[:kickoff].value();

        if (elapsed < 0) {
            return STATUS_UPCOMING;
        } else if (elapsed < ASSUMED_GAME_LENGTH_SEC) {
            return STATUS_LIVE;
        } else if (elapsed < FINAL_WINDOW_END_SEC) {
            return STATUS_FINAL;
        }
        return STATUS_PAST;
    }

    // ========================================================================
    // Implementation details below
    // ========================================================================

    function _loadSchedule() as Lang.Array<Lang.Dictionary> {
        var stored = ScheduleStore.loadGames();
        if (stored == null) {
            return [];
        }
        return _hydrateStored(stored);
    }

    //
    // Convert ScheduleStore's persistable shape (kickoff as Number epoch
    // seconds, String dict keys) into the Time.Moment-bearing dictionary
    // with Symbol keys that the view code reads.
    //
    function _hydrateStored(rawArr as Lang.Array<Lang.Dictionary>) as Lang.Array<Lang.Dictionary> {
        var out = [];
        for (var i = 0; i < rawArr.size(); i++) {
            var raw = rawArr[i];
            var kickoffSec = raw["kickoffSec"];
            if (kickoffSec == null) { continue; }
            out.add({
                :opponent  => raw["opponent"],
                :home      => raw["home"],
                :kickoff   => new Time.Moment(kickoffSec),
                :confirmed => raw["confirmed"]
            });
        }
        return out;
    }
}
