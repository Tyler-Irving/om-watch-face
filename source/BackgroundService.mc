using Toybox.Background;
using Toybox.Communications;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

//
// BackgroundService.mc — Toybox.Background.ServiceDelegate subclass that
// fetches the Ole Miss schedule, writes it to Storage, and re-registers
// itself for the next wake-up using a self-rescheduling cadence:
//
//   * No game today / kickoff > 24h away  → wake again in 24h (daily ping)
//   * Next game inside the next 24h       → wake at kickoff
//   * Inside the live window (kickoff →
//     kickoff + 4h30m)                    → wake again in 15 min
//
// Connect IQ enforces a 5-minute floor between temporal events; the helper
// _registerNextWake() clamps to that floor so the OS doesn't drop our
// registration silently.
//
// Phone proximity caveat: temporal events only fire while the watch is paired
// with Garmin Connect Mobile over BLE. Missed wake-ups are *not* caught up
// when the phone reconnects — only the next scheduled event fires.
//
// Annotated (:background) so the compiler builds this class into the
// background process target (and excludes it from the foreground build when
// the jungle adds an annotation-based exclusion rule).
//
(:background)
class BackgroundService extends System.ServiceDelegate {

    // ESPN's free, unauthenticated public API. Team ID 145 = Ole Miss Rebels.
    // Unofficial — can break or rate-limit without notice. If the response
    // outgrows Connect IQ's per-request JSON size limit (varies by device,
    // typically tens of KB), swap this for a slim proxy that returns just
    // {opponent, kickoffSec, confirmed, status, home} tuples.
    private const SCHEDULE_URL =
        "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/145/schedule";

    // Polling cadence + live-window length. Match the values the user agreed
    // to in the design discussion; tweak here, not at the call sites.
    private const LIVE_POLL_INTERVAL_SEC = 15 * 60;
    private const LIVE_WINDOW_SEC        = 4 * 3600 + 30 * 60;
    private const DAILY_INTERVAL_SEC     = 24 * 3600;

    // Connect IQ's hard floor for temporal event scheduling.
    private const MIN_INTERVAL_SEC = 5 * 60;

    // Ole Miss's ESPN team id, used to decide which competitor in a game
    // dictionary is "us" vs "the opponent".
    private const OLE_MISS_TEAM_ID = "145";

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    //
    // Fired by the OS when our previously-registered temporal event matures.
    // We don't get any context here — we have to look at the wall clock and
    // the schedule we already have to decide what to do next.
    //
    function onTemporalEvent() {
        Communications.makeWebRequest(
            SCHEDULE_URL,
            {},
            {
                :method       => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
    }

    //
    // makeWebRequest callback. responseCode is the HTTP status, OR a negative
    // Connect IQ error code (e.g. -403 for response-too-large). data spans
    // Dictionary | String | PersistedContent.Iterator | Null per the SDK
    // signature; we runtime-check for a Dictionary before parsing.
    //
    function onResponse(
        responseCode as Lang.Number,
        data as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        if (responseCode == 200 && data instanceof Lang.Dictionary) {
            var games = _parseEspn(data);
            ScheduleStore.saveGames(games);
            _scheduleNextWake(games);
        } else {
            ScheduleStore.setError("HTTP " + responseCode);
            // On failure, fall back to the daily cadence rather than retrying
            // immediately — the floor prevents a tight loop even if we tried.
            _registerNextWake(Time.now().value() + DAILY_INTERVAL_SEC);
        }
        // Background.exit() terminates this background process and (when the
        // foreground app is in scope) delivers a callback to onBackgroundData.
        // Passing null keeps it lightweight — Storage already holds the data.
        Background.exit(null);
    }

    // ========================================================================
    // Reschedule logic
    // ========================================================================

    //
    // Choose the next wake time based on the freshly-fetched schedule.
    // See the "self-rescheduling cadence" comment at the top of this file.
    //
    private function _scheduleNextWake(games as Lang.Array<Lang.Dictionary>) {
        var nowSec = Time.now().value();
        var todaysGame = _findGameToday(games, nowSec);

        if (todaysGame != null) {
            var kickoff = todaysGame[:kickoffSec];
            var elapsed = nowSec - kickoff;

            if (elapsed >= 0 && elapsed < LIVE_WINDOW_SEC) {
                // Inside the live window — fast-poll.
                _registerNextWake(nowSec + LIVE_POLL_INTERVAL_SEC);
                ScheduleStore.setPollMode(ScheduleStore.POLL_MODE_LIVE);
                return;
            }
        }

        // Not in a live window. If a kickoff is coming up within 24h, wake
        // exactly at kickoff so we slide cleanly into live polling. (If we
        // only ever scheduled rolling 24h pings, a kickoff that fell between
        // pings could miss the live-window entry.)
        var nextKickoff = _findNextKickoffWithin(games, nowSec, DAILY_INTERVAL_SEC);
        if (nextKickoff != null) {
            _registerNextWake(nextKickoff);
        } else {
            _registerNextWake(nowSec + DAILY_INTERVAL_SEC);
        }
        ScheduleStore.setPollMode(ScheduleStore.POLL_MODE_DAILY);
    }

    //
    // Clamps to the 5-minute floor and registers the temporal event. Any
    // previously-registered event is replaced — only one can be pending at
    // a time per app, so there's nothing to clean up first.
    //
    private function _registerNextWake(targetSec as Lang.Number) {
        var nowSec = Time.now().value();
        var minSec = nowSec + MIN_INTERVAL_SEC;
        if (targetSec < minSec) {
            targetSec = minSec;
        }
        Background.registerForTemporalEvent(new Time.Moment(targetSec));
    }

    //
    // Returns the game whose kickoff falls in the same UTC day as `nowSec`,
    // or null if none. We use UTC-day buckets to match the way the rest of
    // the project stores kickoffs (see Schedule._utcMoment).
    //
    private function _findGameToday(
        games as Lang.Array<Lang.Dictionary>,
        nowSec as Lang.Number
    ) as Lang.Dictionary or Null {
        var dayStart = nowSec - (nowSec % 86400);
        var dayEnd   = dayStart + 86400;
        for (var i = 0; i < games.size(); i++) {
            var ko = games[i][:kickoffSec];
            if (ko != null && ko >= dayStart && ko < dayEnd) {
                return games[i];
            }
        }
        return null;
    }

    //
    // Earliest future kickoff within `windowSec` seconds, or null.
    //
    private function _findNextKickoffWithin(
        games as Lang.Array<Lang.Dictionary>,
        nowSec as Lang.Number,
        windowSec as Lang.Number
    ) as Lang.Number or Null {
        var earliest = null;
        for (var i = 0; i < games.size(); i++) {
            var ko = games[i][:kickoffSec];
            if (ko != null && ko > nowSec && ko < nowSec + windowSec) {
                if (earliest == null || ko < earliest) {
                    earliest = ko;
                }
            }
        }
        return earliest;
    }

    // ========================================================================
    // ESPN response parsing
    // ========================================================================

    //
    // Map the ESPN team-schedule response to the storage shape Schedule.mc
    // expects. Defensive at every step — ESPN occasionally returns events
    // with missing fields (TBD opponents, postponed games), and we don't want
    // a single malformed entry to drop the whole list.
    //
    private function _parseEspn(json as Lang.Dictionary) as Lang.Array<Lang.Dictionary> {
        var out = [];
        var events = json["events"];
        if (events == null) {
            return out;
        }
        for (var i = 0; i < events.size(); i++) {
            var parsed = _parseEvent(events[i]);
            if (parsed != null) {
                out.add(parsed);
            }
        }
        return out;
    }

    //
    // Pull a single event dictionary out of ESPN's response. Returns null if
    // the event is too malformed to use (e.g. missing date).
    //
    private function _parseEvent(e as Lang.Dictionary) as Lang.Dictionary or Null {
        var kickoffSec = _parseIso(e["date"]);
        if (kickoffSec == null) {
            return null;
        }

        var opponent = "TBD";
        var isHome = false;
        var competitions = e["competitions"];
        if (competitions != null && competitions.size() > 0) {
            var competitors = competitions[0]["competitors"];
            if (competitors != null) {
                for (var c = 0; c < competitors.size(); c++) {
                    var comp = competitors[c];
                    var team = comp["team"];
                    if (team == null) { continue; }
                    if (team["id"].equals(OLE_MISS_TEAM_ID)) {
                        isHome = comp["homeAway"].equals("home");
                    } else {
                        opponent = team["displayName"];
                    }
                }
            }
        }

        // ESPN flags TBD-time games via the status detail string. The watch
        // face renders "TBD" instead of a kickoff time when confirmed=false.
        var confirmed = true;
        var statusName = "STATUS_SCHEDULED";
        var status = e["status"];
        if (status != null && status["type"] != null) {
            var type = status["type"];
            if (type["name"] != null) {
                statusName = type["name"];
            }
            var detail = type["detail"];
            if (detail != null && detail.find("TBD") != null) {
                confirmed = false;
            }
        }

        return {
            :opponent   => opponent,
            :home       => isHome,
            :kickoffSec => kickoffSec,
            :confirmed  => confirmed,
            :status     => statusName
        };
    }

    //
    // ISO 8601 → epoch seconds, assuming the trailing "Z" UTC suffix that
    // ESPN uses (e.g. "2025-09-13T20:30Z"). Returns null on any parse failure
    // so the caller can drop the malformed event.
    //
    // We don't import a date-parsing library; the substring/toNumber dance
    // here is small and avoids dragging in extra code into the constrained
    // background-process memory budget.
    //
    private function _parseIso(s as Lang.String or Null) as Lang.Number or Null {
        if (s == null || s.length() < 16) {
            return null;
        }
        var year   = s.substring(0,  4).toNumber();
        var month  = s.substring(5,  7).toNumber();
        var day    = s.substring(8, 10).toNumber();
        var hour   = s.substring(11, 13).toNumber();
        var minute = s.substring(14, 16).toNumber();
        if (year == null || month == null || day == null
                || hour == null || minute == null) {
            return null;
        }
        return _utcSec(year, month, day, hour, minute);
    }

    //
    // Same UTC-epoch math as Schedule._utcMoment, kept here so the background
    // process doesn't have to depend on the foreground Schedule module. Two
    // copies of ~10 lines of arithmetic is cheaper than the alternative.
    //
    private function _utcSec(year, month, day, hour, minute) as Lang.Number {
        var days = 0;
        for (var y = 1970; y < year; y++) {
            days += _isLeap(y) ? 366 : 365;
        }
        var monthDays = [31, _isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        for (var m = 0; m < month - 1; m++) {
            days += monthDays[m];
        }
        days += day - 1;
        return days * 86400 + hour * 3600 + minute * 60;
    }

    private function _isLeap(year) as Lang.Boolean {
        if (year % 400 == 0) { return true; }
        if (year % 100 == 0) { return false; }
        if (year % 4 == 0)   { return true; }
        return false;
    }
}
