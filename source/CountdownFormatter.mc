using Toybox.Lang;

//
// CountdownFormatter.mc — turns a raw seconds-until-kickoff number into the
// short string the watch face renders ("2d 14h 32m" or "14h 32m"). The
// LIVE / FINAL / TBD strings are decided in the view based on game status,
// so this helper only owns the duration → human-readable text mapping.
//
module CountdownFormatter {

    //
    // Format a non-negative number of seconds as either "Xd Yh Zm" (>= 1 day)
    // or "Yh Zm" (< 1 day). Negative inputs are clamped to zero.
    //
    // Lang.format("$1$:$2$", [...]) is Monkey C's printf — positional tokens
    // $1$, $2$, ... pull from the supplied Array. We use Number.format("%02d")
    // to zero-pad minutes for a tidy display ("14h 03m" rather than "14h 3m").
    //
    function format(secondsUntilKickoff) {
        if (secondsUntilKickoff < 0) {
            secondsUntilKickoff = 0;
        }

        var days    = secondsUntilKickoff / 86400;
        var afterD  = secondsUntilKickoff % 86400;
        var hours   = afterD / 3600;
        var afterH  = afterD % 3600;
        var minutes = afterH / 60;

        if (days > 0) {
            return Lang.format("$1$d $2$h $3$m",
                [days, hours, minutes.format("%02d")]);
        }
        return Lang.format("$1$h $2$m",
            [hours, minutes.format("%02d")]);
    }
}
