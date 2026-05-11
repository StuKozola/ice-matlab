function tt = history(session, symbol, opts)
%HISTORY Daily+ historical bars from /xhist.
%   tt = ice.api.history(session, "IBM", NBars=5)
%   tt = ice.api.history(session, "IBM", StartDate=datetime(2020,1,1), EndDate=datetime(2020,12,31), BarInterval="weekly")
%
%   Returns a timetable indexed by datetime (UTC). Per the 2025-12-17 ICE
%   API change, startdate/enddate are sent as UTC+0.

arguments
    session ice.api.Session
    symbol (1,1) string
    opts.StartDate datetime = NaT
    opts.EndDate datetime = NaT
    opts.NBars (1,1) double = NaN
    opts.BarInterval (1,1) string = ""   % daily, weekly, monthly, quarterly, yearly, 2d, 3w, 4m
    opts.Currency (1,1) string = ""
    opts.ContChart (1,1) logical = false
    opts.NullBar (1,1) logical = false
    opts.Split (1,1) logical = true
end

params = struct();
params.symbol = symbol;
if ~isnat(opts.StartDate)
    params.startdate = formatDate(opts.StartDate);
end
if ~isnat(opts.EndDate)
    params.enddate = formatDate(opts.EndDate);
end
if ~isnan(opts.NBars)
    params.options_nbars = string(opts.NBars);
end
if strlength(opts.BarInterval) > 0
    params.options_barintv = opts.BarInterval;
end
if strlength(opts.Currency) > 0
    params.options_currency = opts.Currency;
end
if opts.ContChart
    params.options_contchart = "t";
end
if opts.NullBar
    params.options_nullbar = "t";
end
if ~opts.Split
    params.options_split = "f";
end

xml = session.request("xhist", params);
tt = parseHistXml(xml);
end

function s = formatDate(d)
% ICE expects MM/DD/YYYY for daily, MM/DD/YYYY:HH:mm:SS for intraday.
d.TimeZone = "UTC";
s = string(d, "MM/dd/yyyy");
end
