function tt = intradayHistory(session, symbol, opts)
%INTRADAYHISTORY Intraday aggregated bars from /xtick.
%   tt = ice.api.intradayHistory(session, "IBM", Period="i1", NBars=20)
%   tt = ice.api.intradayHistory(session, "IBM", Period="i5", StartDate=..., EndDate=...)
%
%   Period format:
%     "i<minutes>" — intraday bars at that minute interval (e.g. "i1", "i5").
%
%   Returns a timetable indexed by datetime (UTC). Per the 2025-12-17 ICE
%   API change, startdate/enddate are sent as UTC+0. Max 43,200 bars per
%   request per the ICE limits.

arguments
    session ice.api.Session
    symbol (1,1) string
    opts.Period (1,1) string = "i1"
    opts.StartDate datetime = NaT
    opts.EndDate datetime = NaT
    opts.NBars (1,1) double = NaN
    opts.Exchange (1,1) string = ""
    opts.FormT (1,1) logical = false
    opts.OutSession (1,1) logical = true
    opts.NullBar (1,1) logical = false
    opts.Settlement (1,1) logical = true
    opts.Split (1,1) logical = false
    opts.Forward (1,1) logical = false
    opts.DecimalVolume (1,1) logical = false
end

params = struct();
params.symbol = symbol;
params.period = opts.Period;

if ~isnat(opts.StartDate)
    params.startdate = formatDateTime(opts.StartDate);
end
if ~isnat(opts.EndDate)
    params.enddate = formatDateTime(opts.EndDate);
end
if ~isnan(opts.NBars)
    params.options_nbars = string(opts.NBars);
end
if strlength(opts.Exchange) > 0
    params.options_exchange = opts.Exchange;
end
if opts.FormT;        params.options_formt        = "T"; end
if ~opts.OutSession;  params.options_outsession   = "F"; end
if opts.NullBar;      params.options_nullbar      = "T"; end
if ~opts.Settlement;  params.options_settlement   = "F"; end
if opts.Split;        params.options_split        = "T"; end
if opts.Forward;      params.options_forward      = "T"; end
if opts.DecimalVolume;params.options_decimalvolume= "T"; end

xml = session.request("xtick", params);
tt = parseHistXml(xml);
end

function s = formatDateTime(d)
d.TimeZone = "UTC";
s = string(d, "MM/dd/yyyy:HH:mm:ss");
end
