function tbl = flexHistory(session, symbol, opts)
%FLEXHISTORY Historical data from /flexhistory (weather, mortgage, vessel, etc.).
%   tbl = ice.api.flexHistory(session, "KORH MR0!-GEFS", ...
%       StartDate=datetime(2023,8,20), EndDate=datetime(2023,8,30), ...
%       Columns=["tmp_avg_2m"])
%
%   Returns a table whose columns mirror the dynamic <header> schema in
%   the response. Compound fields (e.g. RT_BarData with open/high/low/avg
%   sub-elements) get one MATLAB column per sub-element, named
%   <field>_<element>.
%
%   Time-typed columns are converted to datetime (UTC, from the
%   epoch-second values ICE returns).

arguments
    session ice.api.Session
    symbol (1,1) string
    opts.StartDate datetime = NaT
    opts.EndDate datetime = NaT
    opts.Period (1,1) string = ""            % t, i<n>, daily, weekly, monthly, yearly
    opts.Columns (1,:) string = string.empty
    opts.TimeSeriesRef (1,1) string = ""     % e.g. "interval_start", "exchange_time"
    opts.ListExch (1,1) string = ""
    opts.NBars (1,1) double = NaN
    opts.BarLength (1,1) double = NaN
    opts.Flex (1,1) logical = true           % defaults to true; columns option requires it
end

params = struct();
params.symbol = symbol;
if ~isnat(opts.StartDate)
    params.startdate = formatDate(opts.StartDate, opts.Period);
end
if ~isnat(opts.EndDate)
    params.enddate = formatDate(opts.EndDate, opts.Period);
end
if strlength(opts.Period) > 0
    params.period = opts.Period;
end
if opts.Flex
    params.options_flex = "T";
end
if ~isempty(opts.Columns)
    params.options_columns = strjoin(opts.Columns, ",");
end
if strlength(opts.TimeSeriesRef) > 0
    params.options_timeseriesref = opts.TimeSeriesRef;
end
if strlength(opts.ListExch) > 0
    params.options_listexch = opts.ListExch;
end
if ~isnan(opts.NBars)
    params.options_nbars = string(opts.NBars);
end
if ~isnan(opts.BarLength)
    params.options_bar_length = string(opts.BarLength);
end

xml = session.request("flexhistory", params);
tbl = parseFlexXml(xml);
end

function s = formatDate(d, period)
% Tick / intraday: MM/DD/YYYY:HH:mm:SS. Interday: MM/DD/YYYY. Defaults to
% interday when period is empty.
d.TimeZone = "UTC";
isIntraday = startsWith(period, "i") || period == "t";
if isIntraday
    s = string(d, "MM/dd/yyyy:HH:mm:ss");
else
    s = string(d, "MM/dd/yyyy");
end
end
