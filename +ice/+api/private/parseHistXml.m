function tt = parseHistXml(xml)
%PARSEHISTXML Convert /xhist or /xtick XML to a timetable.
%   Both endpoints share the same root <xhist symbol="..."> shape; the
%   only difference is that /xtick rows carry a time attribute and may
%   omit openinterest.
%
%   Returns a timetable indexed by datetime, with double price columns
%   and double volume / openinterest where present. UTC is assumed for
%   both date and time per the 2025-12-17 API change.

arguments
    xml (1,1) string
end

xml = strip(xml);
if hasException(xml)
    raiseFromException(xml);
end

% readstruct needs a file; write to a temp file. Could be optimized later
% by streaming via xmlread + DOM, but readstruct's struct-of-arrays output
% is much faster downstream than DOM walking.
tmp = string(tempname()) + ".xml";
fid = fopen(tmp, "w", "n", "UTF-8");
cleanup = onCleanup(@() safeDelete(tmp));
fwrite(fid, uint8(char(xml)));
fclose(fid);

s = readstruct(tmp, FileType="xml");

% Row element is "bar" on live xhist responses but "r" in the docs' sample
% XML (the spec XSD uses <bar>, the sample uses <r>). Handle both.
if isfield(s, "bar")
    rows = s.bar;
elseif isfield(s, "r")
    rows = s.r;
elseif isfield(s, "tick")   % xtick tick-level mode (not bar mode)
    rows = s.tick;
else
    tt = timetable();
    tt = addprop(tt, "symbol", "table");
    if isfield(s, "symbolAttribute")
        tt.Properties.CustomProperties.symbol = string(s.symbolAttribute);
    end
    return
end

n = numel(rows);
dates = strings(n, 1);
times = strings(n, 1);
opens = nan(n,1); highs = nan(n,1); lows = nan(n,1);
closes = nan(n,1); vols = nan(n,1); oi = nan(n,1);

for k = 1:n
    row = rows(k);
    % Row timestamp comes either as a "date" attribute (xhist, sample-style),
    % a "datetime" attribute (xtick bar element per XSD), or as separate
    % date + time attributes.
    if isfield(row, "datetimeAttribute") && ~ismissing(row.datetimeAttribute)
        dates(k) = string(row.datetimeAttribute);
    elseif isfield(row, "dateAttribute")
        dates(k) = string(row.dateAttribute);
    end
    if isfield(row, "timeAttribute"); times(k) = string(row.timeAttribute); end
    if isfield(row, "open"); opens(k) = toDouble(row.open); end
    if isfield(row, "high"); highs(k) = toDouble(row.high); end
    if isfield(row, "low");  lows(k)  = toDouble(row.low);  end
    if isfield(row, "close");closes(k)= toDouble(row.close);end
    if isfield(row, "volume");vols(k) = toDouble(row.volume);end
    if isfield(row, "openinterest"); oi(k) = toDouble(row.openinterest); end
end

% Combine date + time (when present) into a single datetime.
hasTime = any(strlength(times) > 0);
when = parseTimestamps(dates, times, hasTime);

tt = timetable(when, opens, highs, lows, closes, vols, oi, ...
    VariableNames=["open","high","low","close","volume","openinterest"]);
tt = addprop(tt, "symbol", "table");
if isfield(s, "symbolAttribute")
    tt.Properties.CustomProperties.symbol = string(s.symbolAttribute);
end
end

function when = parseTimestamps(dates, times, hasTime)
% ICE varies the date format across endpoints:
%   xhist sample (doc):  yyyy/MM/dd
%   xhist live:          yyyy-MM-dd
%   xtick XSD:           ISO 8601 datetime in the datetime attribute
% Detect format from the first non-empty value, fall back to ISO.
firstDate = "";
for k = 1:numel(dates)
    if strlength(dates(k)) > 0
        firstDate = dates(k);
        break;
    end
end

if hasTime
    combined = dates + " " + times;
    inputFmt = pickFormat(firstDate, true);
    when = datetime(combined, InputFormat=inputFmt, TimeZone="UTC");
elseif contains(firstDate, "T")
    % Live xtick sends "yyyy-MM-ddTHH:mm:ssZ"; strip the trailing Z (or any
    % timezone suffix) since we're already declaring TimeZone="UTC".
    cleaned = regexprep(dates, "Z$", "");
    when = datetime(cleaned, InputFormat="uuuu-MM-dd'T'HH:mm:ss", TimeZone="UTC");
else
    inputFmt = pickFormat(firstDate, false);
    when = datetime(dates, InputFormat=inputFmt, TimeZone="UTC");
end
end

function fmt = pickFormat(sample, hasTime)
if contains(sample, "-")
    base = "uuuu-MM-dd";
elseif contains(sample, "/")
    base = "yyyy/MM/dd";
else
    base = "yyyyMMdd";
end
if hasTime
    fmt = base + " HH:mm:ss";
else
    fmt = base;
end
end

function v = toDouble(x)
if ischar(x) || isstring(x)
    v = str2double(x);
else
    v = double(x);
end
end

function raiseFromException(xml)
% ICE returns <xcpt n="…"/> or <exception>…</exception> for API errors.
msg = regexp(xml, '<xcpt[^>]*n="([^"]*)"', "tokens", "once");
if isempty(msg)
    msg = regexp(xml, '<exception>([^<]*)</exception>', "tokens", "once");
end
if isempty(msg)
    error("ice:api:ResponseError", "Server returned an error: %s", xml);
end
error("ice:api:ResponseError", "Server returned an error: %s", string(msg{1}));
end

function tf = hasException(xml)
% True if the response is an ICE error envelope rather than data.
tf = contains(xml, "<xcpt") || ...
     ~isempty(regexp(xml, '<exception\b', "once"));
end

function safeDelete(p)
if isfile(p); try; delete(p); catch; end; end %#ok<NOSEMI>
end
