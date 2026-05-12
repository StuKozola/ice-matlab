classdef Progress < handle
    %Progress Lightweight CLI progress bar for long loops.
    %   bar = ice.util.Progress(total, "label");
    %   for k = 1:total; ...; bar.tick(); end
    %   bar.done();
    %
    %   Renders one line using \r to overwrite. In MATLAB -batch mode the
    %   carriage returns appear as separate lines (still useful in a log).
    %   Throttled so very fast loops don't flood the screen.

    properties (SetAccess = immutable)
        Total (1,1) double
        Label (1,1) string
        Width (1,1) double = 30
    end

    properties (Access = private)
        Count (1,1) double = 0
        Started (1,1) datetime
        LastRendered (1,1) datetime
        Interval (1,1) duration = seconds(0.2)
        IsTty (1,1) logical
    end

    methods
        function obj = Progress(total, label, opts)
            arguments
                total (1,1) double {mustBePositive,mustBeInteger}
                label (1,1) string = ""
                opts.Width (1,1) double = 30
                opts.Interval (1,1) duration = seconds(0.2)
            end
            obj.Total = total;
            obj.Label = label;
            obj.Width = opts.Width;
            obj.Interval = opts.Interval;
            obj.Started = datetime("now");
            obj.LastRendered = datetime("now") - days(1);
            obj.IsTty = ~batchStartupOptionUsed;
            obj.render(true);
        end

        function tick(obj, n)
            arguments
                obj
                n (1,1) double = 1
            end
            obj.Count = obj.Count + n;
            now = datetime("now");
            if obj.Count >= obj.Total || (now - obj.LastRendered) >= obj.Interval
                obj.render(false);
                obj.LastRendered = now;
            end
        end

        function done(obj)
            obj.Count = obj.Total;
            obj.render(false);
            fprintf("\n");
        end
    end

    methods (Access = private)
        function render(obj, isFirst)
            frac = min(obj.Count / obj.Total, 1);
            filled = round(frac * obj.Width);
            bar = [repmat('=', 1, filled), repmat('.', 1, obj.Width - filled)];
            elapsed = datetime("now") - obj.Started;
            elapsedSec = max(seconds(elapsed), 0.001);
            rate = obj.Count / elapsedSec;
            if rate > 0 && obj.Count < obj.Total
                etaSec = (obj.Total - obj.Count) / rate;
                etaStr = sprintf(" eta %s", formatDur(etaSec));
            else
                etaStr = "";
            end
            line = sprintf("%-20s [%s] %d/%d (%.1f%%)%s", ...
                truncate(obj.Label, 20), bar, obj.Count, obj.Total, ...
                100 * frac, etaStr);
            if obj.IsTty && ~isFirst
                fprintf("\r%s", line);
            else
                fprintf("%s\n", line);
            end
        end
    end
end

function s = formatDur(sec)
if sec < 60
    s = sprintf("%.0fs", sec);
elseif sec < 3600
    s = sprintf("%dm%02ds", floor(sec/60), mod(round(sec), 60));
else
    s = sprintf("%dh%02dm", floor(sec/3600), mod(floor(sec/60), 60));
end
end

function s = truncate(s, n)
if strlength(s) > n
    s = extractBefore(s, n) + "…";
end
end
