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

if ~isfield(s, "r")
    tt = timetable();
    tt = addprop(tt, "symbol", "table");
    if isfield(s, "symbolAttribute")
        tt.Properties.CustomProperties.symbol = string(s.symbolAttribute);
    end
    return
end

n = numel(s.r);
dates = strings(n, 1);
times = strings(n, 1);
opens = nan(n,1); highs = nan(n,1); lows = nan(n,1);
closes = nan(n,1); vols = nan(n,1); oi = nan(n,1);

for k = 1:n
    row = s.r(k);
    if isfield(row, "dateAttribute"); dates(k) = string(row.dateAttribute); end
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
if hasTime
    when = datetime(dates + " " + times, ...
        InputFormat="yyyy/MM/dd HH:mm:ss", TimeZone="UTC");
else
    when = datetime(dates, InputFormat="yyyy/MM/dd", TimeZone="UTC");
end

tt = timetable(when, opens, highs, lows, closes, vols, oi, ...
    VariableNames=["open","high","low","close","volume","openinterest"]);
tt = addprop(tt, "symbol", "table");
if isfield(s, "symbolAttribute")
    tt.Properties.CustomProperties.symbol = string(s.symbolAttribute);
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
