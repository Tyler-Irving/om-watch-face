using Toybox.Time;
using Toybox.Lang;

//
// Schedule.mc — the Ole Miss football schedule and helpers for finding the
// "next game" relative to the current time.
//
// Today this is a static array compiled into the watch face. Tomorrow it
// will be a Communications.makeWebRequest call to a backend that returns
// the same shape; the rest of the app already reads the schedule through
// getNextGame() / getGameStatus() so nothing else has to change.
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

    // ----- Demo / development knobs -----------------------------------------
    // When true, getSchedule() injects a synthetic game two days from now so
    // the simulator always has something to count down to. Flip to false to
    // test against the real (potentially all-in-the-past) static schedule.
    const INCLUDE_DEMO_GAME = true;

    // Cached schedule — built once on first read. The static schedule never
    // changes at runtime, so there is no reason to rebuild Moments on every
    // onUpdate().
    var _cachedSchedule = null;

    //
    // Returns the full schedule as an Array of Dictionary entries, each:
    //   :opponent  → String, e.g. "Alabama"
    //   :home      → Boolean, true for home (renders "vs"), false for away ("@")
    //   :kickoff   → Time.Moment, kickoff in UTC
    //   :confirmed → Boolean, false → render "TBD" instead of a countdown
    //
    // TODO(network): swap _buildStaticSchedule() for a Communications
    // .makeWebRequest call that returns the same Array<Dictionary> shape.
    // The rest of the file (getNextGame, getGameStatus) is consumer-side and
    // does not care where the data came from.
    //
    function getSchedule() as Lang.Array<Lang.Dictionary> {
        if (_cachedSchedule == null) {
            _cachedSchedule = _buildStaticSchedule();
            if (INCLUDE_DEMO_GAME) {
                _cachedSchedule.add(_buildDemoGame());
            }
        }
        return _cachedSchedule;
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

    //
    // The 2025 Ole Miss Rebels regular season. Times are best-effort UTC for
    // the announced kickoff slot; replace with authoritative values as they
    // are confirmed. Games whose kickoff time is still TBD are flagged with
    // confirmed=false and a placeholder kickoff at 17:00 UTC of the game day,
    // so they still sort correctly even though the view will render "TBD".
    //
    function _buildStaticSchedule() {
        return [
            // opponent,          home,  Y    M   D   h   m   confirmed
            _buildGame("Georgia State",     true,  2025,  8, 30, 23,  0, true),
            _buildGame("Kentucky",          true,  2025,  9,  6, 20, 15, true),
            _buildGame("Arkansas",          false, 2025,  9, 13, 20, 30, true),
            _buildGame("Tulane",            true,  2025,  9, 20, 21,  0, true),
            _buildGame("LSU",               true,  2025,  9, 27, 23, 30, true),
            _buildGame("Washington State",  true,  2025, 10, 11, 21,  0, true),
            _buildGame("Georgia",           false, 2025, 10, 18, 20, 30, true),
            _buildGame("Oklahoma",          true,  2025, 10, 25, 21,  0, true),
            _buildGame("South Carolina",    false, 2025, 11,  1, 17,  0, false),
            _buildGame("The Citadel",       true,  2025, 11, 15, 21,  0, true),
            _buildGame("Florida",           false, 2025, 11, 22, 17,  0, false),
            _buildGame("Mississippi State", true,  2025, 11, 28, 19, 30, true)
        ];
    }

    //
    // A synthetic "game" two days from right-now, used so the simulator
    // always shows a working countdown regardless of the calendar date.
    //
    function _buildDemoGame() {
        var twoDays = new Time.Duration(2 * 24 * 3600);
        return {
            :opponent  => "Demo Opponent",
            :home      => true,
            :kickoff   => Time.now().add(twoDays),
            :confirmed => true
        };
    }

    //
    // Constructs a game dictionary from primitive arguments. Kickoff is built
    // as a UTC Moment via _utcMoment so the schedule is timezone-independent.
    //
    function _buildGame(opponent, isHome, year, month, day, hour, minute, confirmed) {
        return {
            :opponent  => opponent,
            :home      => isHome,
            :kickoff   => _utcMoment(year, month, day, hour, minute),
            :confirmed => confirmed
        };
    }

    //
    // Returns a Time.Moment representing the given UTC date/time.
    //
    // Toybox's Gregorian.moment() interprets its dictionary in *local* time
    // and there is no built-in UTC variant, so we compute the epoch seconds
    // ourselves and hand them to the Moment constructor (which takes seconds
    // since 1970-01-01 UTC).
    //
    function _utcMoment(year, month, day, hour, minute) {
        var days = 0;

        // Whole years from 1970 up to (but not including) `year`.
        for (var y = 1970; y < year; y++) {
            days += _isLeapYear(y) ? 366 : 365;
        }

        // Days for completed months in the current year.
        var monthDays = [31, _isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        for (var m = 0; m < month - 1; m++) {
            days += monthDays[m];
        }

        // Days within the current month.
        days += day - 1;

        var seconds = days * 86400 + hour * 3600 + minute * 60;
        return new Time.Moment(seconds);
    }

    function _isLeapYear(year) {
        if (year % 400 == 0) { return true; }
        if (year % 100 == 0) { return false; }
        if (year % 4 == 0)   { return true; }
        return false;
    }
}
