using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;
using Toybox.Application;

//
// OleMissWatchFaceView.mc — the visible watch face. Layout, top to bottom:
//
//   ┌──────────────────────────────────┐
//   │                                  │
//   │            12:34   ← time        │
//   │          Sat, Nov 9 ← date       │
//   │                                  │
//   │     [ Ole Miss logo background ] │
//   │                                  │
//   │          vs Alabama ← opponent   │
//   │          2d 14h 32m ← countdown  │
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
    private const TIME_CENTER_Y_RATIO       = 0.24;
    private const DATE_CENTER_Y_RATIO       = 0.38;
    private const OPPONENT_CENTER_Y_RATIO   = 0.72;
    private const COUNTDOWN_CENTER_Y_RATIO  = 0.84;

    // Vertical extents used as clip rects in onPartialUpdate.
    private const TIME_REGION_TOP_RATIO     = 0.14;
    private const TIME_REGION_BOTTOM_RATIO  = 0.34;
    private const KICK_REGION_TOP_RATIO     = 0.66;
    private const KICK_REGION_BOTTOM_RATIO  = 0.92;

    // ----- Cached state -----------------------------------------------------
    private var _logoBitmap;
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
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        _drawLogo(dc);
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

        var y = (_screenHeight * TIME_CENTER_Y_RATIO).toNumber();
        _drawTextWithShadow(dc, _centerX, y, Graphics.FONT_NUMBER_THAI_HOT,
            timeStr, 2);
    }

    private function _drawDate(dc) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        // FORMAT_MEDIUM populates day_of_week and month as 3-letter strings.
        var dateStr = Lang.format("$1$, $2$ $3$",
            [info.day_of_week, info.month, info.day]);

        var y = (_screenHeight * DATE_CENTER_Y_RATIO).toNumber();
        _drawTextWithShadow(dc, _centerX, y, Graphics.FONT_SMALL, dateStr, 1);
    }

    private function _drawKickoffSection(dc) {
        var nextGame = Schedule.getNextGame();

        var line1; // opponent string ("vs Alabama" / "@ LSU") or filler
        var line2; // countdown string, "TBD", "LIVE", "FINAL", or empty

        if (nextGame == null) {
            // No game in the lookahead window → off-season filler.
            line1 = "Hotty Toddy";
            line2 = "";
        } else {
            var prefix = nextGame[:home] ? "vs " : "@ ";
            line1 = prefix + nextGame[:opponent];

            if (!nextGame[:confirmed]) {
                // Time hasn't been announced yet — don't tease a countdown.
                line2 = "TBD";
            } else {
                var status = Schedule.getGameStatus(nextGame);
                if (status == Schedule.STATUS_LIVE) {
                    line2 = "LIVE";
                } else if (status == Schedule.STATUS_FINAL) {
                    line2 = "FINAL";
                } else {
                    var seconds = nextGame[:kickoff].value() - Time.now().value();
                    line2 = CountdownFormatter.format(seconds);
                }
            }
        }

        var y1 = (_screenHeight * OPPONENT_CENTER_Y_RATIO).toNumber();
        var y2 = (_screenHeight * COUNTDOWN_CENTER_Y_RATIO).toNumber();

        _drawTextWithShadow(dc, _centerX, y1, Graphics.FONT_SMALL,  line1, 1);
        _drawTextWithShadow(dc, _centerX, y2, Graphics.FONT_MEDIUM, line2, 2);
    }

    //
    // Renders text in white with a single-pixel-offset black shadow so it
    // remains legible over a busy logo background. The offset is configurable
    // (1 px for small text, 2 px for the giant clock).
    //
    private function _drawTextWithShadow(dc, cx, cy, font, text, offset) {
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + offset, cy + offset, font, text, justify);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, text, justify);
    }

    // ----- Low-power partial-update helpers ---------------------------------

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
