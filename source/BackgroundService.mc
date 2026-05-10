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

    // Slim ESPN proxy (Cloudflare Worker — source in sibling repo
    // om-schedule-proxy). Hits ESPN server-side, strips each event to the five
    // fields the watch uses, returns ~1-2 KB instead of ESPN's ~400 KB so we
    // stay under Connect IQ's per-request JSON cap.
    private const SCHEDULE_URL =
        "https://om-schedule-proxy.tirving.workers.dev/";

    // Polling cadence + live-window length. Match the values the user agreed
    // to in the design discussion; tweak here, not at the call sites.
    private const LIVE_POLL_INTERVAL_SEC = 15 * 60;
    private const LIVE_WINDOW_SEC        = 4 * 3600 + 30 * 60;
    private const DAILY_INTERVAL_SEC     = 24 * 3600;

    // Connect IQ's hard floor for temporal event scheduling.
    private const MIN_INTERVAL_SEC = 5 * 60;

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
            var games = _parseProxy(data);
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
            var kickoff = todaysGame["kickoffSec"];
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
            var ko = games[i]["kickoffSec"];
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
            var ko = games[i]["kickoffSec"];
            if (ko != null && ko > nowSec && ko < nowSec + windowSec) {
                if (earliest == null || ko < earliest) {
                    earliest = ko;
                }
            }
        }
        return earliest;
    }

    // ========================================================================
    // Proxy response parsing
    // ========================================================================

    //
    // The Cloudflare Worker already strips ESPN's payload to the shape we
    // store ({opponent, kickoffSec, confirmed, status, home}), so this is
    // mostly a transcribe-with-defensive-defaults pass — guard against
    // missing fields per entry so one malformed event doesn't drop the rest.
    //
    private function _parseProxy(json as Lang.Dictionary) as Lang.Array<Lang.Dictionary> {
        var out = [];
        // `as` casts narrow the dict/array element types for the type checker;
        // they silence "Cannot determine container type" on the dynamic JSON
        // reads below. Cast to a nullable union so the null guards remain
        // reachable — the runtime check is what actually protects us if the
        // upstream payload is malformed.
        var events = json["events"] as Null or Lang.Array<Lang.Dictionary>;
        if (events == null) {
            return out;
        }
        for (var i = 0; i < events.size(); i++) {
            var e = events[i] as Null or Lang.Dictionary;
            if (e == null) { continue; }

            // kickoffSec is the only field we can't synthesize — without it
            // the entry is useless to the schedule view.
            var kickoffSec = e["kickoffSec"];
            var opponent = e["opponent"];
            if (kickoffSec == null || opponent == null) {
                continue;
            }

            var home      = e["home"];
            var confirmed = e["confirmed"];
            var status    = e["status"];

            // String keys (not symbols) because this dict will be passed to
            // Application.Storage, which rejects symbol-keyed dicts with
            // UnexpectedTypeException.
            out.add({
                "opponent"   => opponent,
                "home"       => (home != null) ? home : false,
                "kickoffSec" => kickoffSec,
                "confirmed"  => (confirmed != null) ? confirmed : true,
                "status"     => (status != null) ? status : "STATUS_SCHEDULED"
            });
        }
        return out;
    }
}
