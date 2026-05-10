using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;
using Toybox.Application;
using Toybox.ActivityMonitor;

//
// OleMissWatchFaceView.mc — the visible watch face. Layout, top to bottom:
//
//   ┌──────────────────────────────────┐
//   │            8432 steps            │  ← steps (top-center)
//   │                       12:34      │  ← time (right)
//   │                       Sat, Nov 9 │  ← date (left-aligned w/ time)
//   │                                  │
//   │     [ Ole Miss logo background ] │
//   │             Alabama ← opponent   │
//   │          Sat 7:30 PM ← kickoff   │
//   │                                  │
//   └──────────────────────────────────┘
//
// onUpdate() does the full repaint (logo + all four text rows). When the
// watch enters always-on / low-power mode, onPartialUpdate() takes over: it
// re-draws only the small clip rects around the time and the countdown,
// leaving the rest of the (unchanging) logo background alone. The clip-rect
// trick is what keeps the partial path within Connect IQ's 30 ms budget on
// AMOLED devices.
//
class OleMissWatchFaceView extends WatchUi.WatchFace {

    // ----- Layout ratios (all relative to screen height/width so any future
    //       Fenix 8 size drops in without re-tuning numbers manually). -----
    // Steps sit at top-center; time and date sit lower-right, sharing a left edge.
    private const STEPS_CENTER_Y_RATIO      = 0.52;
    private const TIME_CENTER_Y_RATIO       = 0.34;
    private const DATE_CENTER_Y_RATIO       = 0.43;
    private const TIME_DATE_LEFT_X_RATIO    = 0.62;
    private const OPPONENT_CENTER_Y_RATIO   = 0.82;
    private const COUNTDOWN_CENTER_Y_RATIO  = 0.89;

    // Vertical extents used as clip rects in onPartialUpdate.
    private const STEPS_REGION_TOP_RATIO    = 0.46;
    private const STEPS_REGION_BOTTOM_RATIO = 0.58;
    private const TIME_REGION_TOP_RATIO     = 0.25;
    private const TIME_REGION_BOTTOM_RATIO  = 0.49;
    private const KICK_REGION_TOP_RATIO     = 0.76;
    private const KICK_REGION_BOTTOM_RATIO  = 0.94;

    // Background fill — sampled from the logo PNG's corner pixel (Ole Miss
    // navy #002147). The logo bitmap is smaller than some target screens
    // (e.g. 416×416 art on the 454×454 Fenix 8 Pro), so we clear with this
    // color and the logo's own padding blends seamlessly into the surround.
    private const BACKGROUND_COLOR = 0x002147;

    // ----- Cached state -----------------------------------------------------
    private var _logoBitmap;
    private var _footprintsBitmap;
    private var _screenWidth;
    private var _screenHeight;
    private var _centerX;
    private var _centerY;

    // Tracks the last minute we rendered text for. onPartialUpdate fires
    // every second; since neither the clock nor the countdown shows seconds,
    // re-drawing only on minute boundaries skips ~59 wasted draws per minute.
    private var _lastRenderedMinute;

    function initialize() {
        WatchFace.initialize();
        _lastRenderedMinute = -1;
    }

    //
    // Called once when the layout is established (and again after a resume
    // from sleep on some devices). Cache anything we need across draws here.
    //
    function onLayout(dc) {
        _screenWidth  = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX      = _screenWidth  / 2;
        _centerY      = _screenHeight / 2;

        // loadResource pulls the bitmap declared in drawables.xml. The
        // Rez.Drawables namespace is generated from resource IDs at compile
        // time — no string lookup at runtime.
        _logoBitmap = WatchUi.loadResource(Rez.Drawables.OleMissLogo);
        _footprintsBitmap = WatchUi.loadResource(Rez.Drawables.FootprintsIcon);
    }

    function onShow() {
    }

    function onHide() {
    }

    //
    // Full repaint, called once per minute (and on show / on settings
    // change). Order matters: clear → logo → text overlays so the logo
    // sits underneath the readable layers.
    //
    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, BACKGROUND_COLOR);
        dc.clear();

        _drawLogo(dc);
        _drawSteps(dc);
        _drawTime(dc);
        _drawDate(dc);
        _drawKickoffSection(dc);

        _lastRenderedMinute = System.getClockTime().min;
    }

    //
    // Low-power tick (called once per second on AMOLED always-on). Only
    // re-renders the regions whose contents can change on a minute boundary.
    // We bail out early if the minute hasn't ticked yet — there's nothing to
    // do until then since neither the time nor the countdown shows seconds.
    //
    function onPartialUpdate(dc) {
        var minute = System.getClockTime().min;
        if (minute == _lastRenderedMinute) {
            return;
        }
        _lastRenderedMinute = minute;

        _redrawStepsRegion(dc);
        _redrawTimeRegion(dc);
        _redrawKickoffRegion(dc);
    }

    function onEnterSleep() {
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        WatchUi.requestUpdate();
    }

    // ========================================================================
    // Drawing helpers
    // ========================================================================

    private function _drawLogo(dc) {
        if (_logoBitmap == null) {
            return;
        }
        var x = _centerX - (_logoBitmap.getWidth()  / 2);
        var y = _centerY - (_logoBitmap.getHeight() / 2);
        dc.drawBitmap(x, y, _logoBitmap);
    }

    private function _drawSteps(dc) {
        // ActivityMonitor.getInfo() can return null very briefly during boot,
        // and .steps itself may be null on devices without a step sensor or
        // before the day's first sample. Default to 0 in either case.
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;
        var stepsStr = _formatSteps(steps);

        var font = Graphics.FONT_XTINY;
        var y = (_screenHeight * STEPS_CENTER_Y_RATIO).toNumber();

        var iconW = (_footprintsBitmap != null) ? _footprintsBitmap.getWidth()  : 0;
        var iconH = (_footprintsBitmap != null) ? _footprintsBitmap.getHeight() : 0;
        var spacing = 6;

        // Anchor the row to the same left edge as the time/date stack.
        var startX = (_screenWidth * TIME_DATE_LEFT_X_RATIO).toNumber();

        if (_footprintsBitmap != null) {
            dc.drawBitmap(startX, y - (iconH / 2), _footprintsBitmap);
        }

        var textX = startX + iconW + spacing;
        _drawTextWithShadow(dc, textX, y, font, stepsStr, 1,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //
    // 0–999 → "847", 1000–9999 → "1.5 K", 10000+ → "15 K".
    //
    private function _formatSteps(steps) {
        if (steps < 1000) {
            return steps.toString();
        }
        var thousands = steps.toFloat() / 1000.0;
        var fmt = (steps < 10000) ? "%.1f" : "%.0f";
        return Lang.format("$1$ K", [thousands.format(fmt)]);
    }

    private function _drawTime(dc) {
        var clockTime = System.getClockTime();
        var hour      = clockTime.hour;
        var minute    = clockTime.min;

        // Pull the user's 12/24-hour preference from the property bag.
        // The property is declared in properties.xml with a Boolean default,
        // so getValue() always returns a Boolean — no null fallback needed.
        var use24h = Application.Properties.getValue("Use24Hour") as Lang.Boolean;

        var timeStr;
        if (use24h) {
            timeStr = Lang.format("$1$:$2$",
                [hour.format("%02d"), minute.format("%02d")]);
        } else {
            var displayHour = hour % 12;
            if (displayHour == 0) {
                displayHour = 12;
            }
            timeStr = Lang.format("$1$:$2$",
                [displayHour.format("%d"), minute.format("%02d")]);
        }

        var x = (_screenWidth  * TIME_DATE_LEFT_X_RATIO).toNumber();
        var y = (_screenHeight * TIME_CENTER_Y_RATIO).toNumber();
        _drawTextWithShadow(dc, x, y, Graphics.FONT_MEDIUM, timeStr, 1,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function _drawDate(dc) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        // FORMAT_MEDIUM populates day_of_week and month as 3-letter strings.
        var dateStr = Lang.format("$1$, $2$ $3$",
            [info.day_of_week, info.month, info.day]);

        var x = (_screenWidth  * TIME_DATE_LEFT_X_RATIO).toNumber();
        var y = (_screenHeight * DATE_CENTER_Y_RATIO).toNumber();
        _drawTextWithShadow(dc, x, y, Graphics.FONT_XTINY, dateStr, 1,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function _drawKickoffSection(dc) {
        var nextGame = Schedule.getNextGame();

        var line1; // opponent name or filler
        var line2; // kickoff time, "TBD", "LIVE", "FINAL", or empty

        if (nextGame == null) {
            // No game in the lookahead window → off-season filler.
            line1 = "Hotty Toddy";
            line2 = "";
        } else {
            line1 = nextGame[:opponent];

            if (!nextGame[:confirmed]) {
                line2 = "TBD";
            } else {
                var status = Schedule.getGameStatus(nextGame);
                if (status == Schedule.STATUS_LIVE) {
                    line2 = "LIVE";
                } else if (status == Schedule.STATUS_FINAL) {
                    line2 = "FINAL";
                } else {
                    line2 = _formatKickoff(nextGame[:kickoff]);
                }
            }
        }

        var y1 = (_screenHeight * OPPONENT_CENTER_Y_RATIO).toNumber();
        var y2 = (_screenHeight * COUNTDOWN_CENTER_Y_RATIO).toNumber();

        var centerJustify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        _drawTextWithShadow(dc, _centerX, y1, Graphics.FONT_XTINY, line1, 1, centerJustify);
        _drawTextWithShadow(dc, _centerX, y2, Graphics.FONT_XTINY, line2, 1, centerJustify);
    }

    //
    // Formats a kickoff Moment as "<DOW> <h>:<mm>[ AM|PM]" in the user's local
    // timezone, honoring the Use24Hour property. Day-of-week is included so a
    // bare "7:30" isn't ambiguous when the game is days away.
    //
    private function _formatKickoff(kickoffMoment) {
        var info = Gregorian.info(kickoffMoment, Time.FORMAT_MEDIUM);
        var hour = info.hour;
        var minute = info.min;

        var use24h = Application.Properties.getValue("Use24Hour") as Lang.Boolean;

        var timeStr;
        if (use24h) {
            timeStr = Lang.format("$1$:$2$",
                [hour.format("%02d"), minute.format("%02d")]);
        } else {
            var displayHour = hour % 12;
            if (displayHour == 0) {
                displayHour = 12;
            }
            var ampm = hour < 12 ? "AM" : "PM";
            timeStr = Lang.format("$1$:$2$ $3$",
                [displayHour.format("%d"), minute.format("%02d"), ampm]);
        }

        return Lang.format("$1$ $2$", [info.day_of_week, timeStr]);
    }

    //
    // Renders text in white with a small black shadow offset so it stays
    // legible over a busy logo background. The (x, y) anchor is interpreted
    // according to the supplied justify flags — pass LEFT|VCENTER for the
    // top-right time/date stack, CENTER|VCENTER for the kickoff strip.
    //
    private function _drawTextWithShadow(dc, x, y, font, text, offset, justify) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + offset, y + offset, font, text, justify);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    // ----- Low-power partial-update helpers ---------------------------------

    //
    // Re-renders the top-of-screen step counter clipped to its narrow band.
    //
    private function _redrawStepsRegion(dc) {
        var top    = (_screenHeight * STEPS_REGION_TOP_RATIO).toNumber();
        var bottom = (_screenHeight * STEPS_REGION_BOTTOM_RATIO).toNumber();
        var height = bottom - top;

        dc.setClip(0, top, _screenWidth, height);
        _drawLogo(dc);
        _drawSteps(dc);
        dc.clearClip();
    }

    //
    // Re-renders the clock + date strip without touching the rest of the
    // screen. We re-draw the logo *clipped to the time band* so the previous
    // minute's pixels can't ghost through underneath the new digits.
    //
    private function _redrawTimeRegion(dc) {
        var top    = (_screenHeight * TIME_REGION_TOP_RATIO).toNumber();
        var bottom = (_screenHeight * TIME_REGION_BOTTOM_RATIO).toNumber();
        var height = bottom - top;

        dc.setClip(0, top, _screenWidth, height);
        _drawLogo(dc);  // drawBitmap respects the active clip rect
        _drawTime(dc);
        _drawDate(dc);
        dc.clearClip();
    }

    //
    // Same idea for the lower kickoff strip.
    //
    private function _redrawKickoffRegion(dc) {
        var top    = (_screenHeight * KICK_REGION_TOP_RATIO).toNumber();
        var bottom = (_screenHeight * KICK_REGION_BOTTOM_RATIO).toNumber();
        var height = bottom - top;

        dc.setClip(0, top, _screenWidth, height);
        _drawLogo(dc);
        _drawKickoffSection(dc);
        dc.clearClip();
    }
}
