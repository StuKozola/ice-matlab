function tt = intradayHistoryRange(session, symbol, startDate, endDate, opts)
%INTRADAYHISTORYRANGE Chunked intraday backfill across an arbitrary window.
%   tt = ice.api.intradayHistoryRange(session, "AAPL", ...
%       datetime(2024,1,1), datetime(2024,6,30), Period="i1")
%
%   /xtick caps each request at 43,200 bars. For a 1-minute (i1) bar a
%   24/7 instrument tops out at 1,440 bars/day, so 30 calendar days is
%   the safe chunk. For a 5-minute (i5) bar it's 150 days. For tick
%   data the cap is unpredictable, so we default to 1-day chunks.
%
%   The function picks a chunk size from Period, issues one request per
%   chunk, and concatenates the results in chronological order with
%   duplicates at chunk boundaries removed by timestamp. All other
%   intradayHistory options pass through unchanged.

arguments
    session ice.api.Session
    symbol (1,1) string
    startDate (1,1) datetime
    endDate (1,1) datetime
    opts.Period (1,1) string = "i1"
    opts.Exchange (1,1) string = ""
    opts.FormT (1,1) logical = false
    opts.OutSession (1,1) logical = true
    opts.NullBar (1,1) logical = false
    opts.Settlement (1,1) logical = true
    opts.Split (1,1) logical = false
    opts.Forward (1,1) logical = false
    opts.DecimalVolume (1,1) logical = false
end

if isnat(startDate) || isnat(endDate)
    error("ice:api:intradayHistoryRange:BadRange", ...
        "StartDate and EndDate are required");
end
if endDate < startDate
    error("ice:api:intradayHistoryRange:BadRange", ...
        "EndDate must be >= StartDate");
end

chunkDays = chunkSizeDays(opts.Period);

% Build chunk windows. Each chunk's end is inclusive of the last bar at
% (chunkEnd - 1 second), and the next chunk starts at chunkEnd so we
% don't gap. Boundary duplicates are handled by post-stitch dedup.
ranges = [];
cursor = startDate;
while cursor <= endDate
    next = min(endDate, cursor + days(chunkDays));
    ranges = [ranges; struct("from", cursor, "to", next)]; %#ok<AGROW>
    if next >= endDate; break; end
    cursor = next;
end

passthrough = rmfield(opts, "Period");
baseNv = struct2nv(passthrough);
ttParts = cell(numel(ranges), 1);
for k = 1:numel(ranges)
    nv = [{"Period", opts.Period, ...
           "StartDate", ranges(k).from, ...
           "EndDate", ranges(k).to}, baseNv];
    ttParts{k} = ice.api.intradayHistory(session, symbol, nv{:});
end

% Concatenate. Skip empty parts; keep the symbol custom property from
% the first non-empty timetable.
nonEmpty = cellfun(@(t) ~isempty(t) && height(t) > 0, ttParts);
if ~any(nonEmpty)
    tt = timetable();
    return
end
ttParts = ttParts(nonEmpty);
tt = vertcat(ttParts{:});

% Dedup on the time index (boundary bars can show up in two chunks).
[~, ia] = unique(tt.Properties.RowTimes, "stable");
tt = tt(ia, :);

% Final sort by time so callers don't have to.
tt = sortrows(tt);
end

function days = chunkSizeDays(period)
% Conservative chunk window in calendar days for each /xtick period.
% Bars/day worst case (24-hour markets):
%   i1  -> 1440/day  -> 30  days < 43200
%   i5  -> 288/day   -> 150 days < 43200
%   t   -> ticks; unbounded -> 1 day
period = lower(period);
if period == "t"
    days = 1;
    return
end
if startsWith(period, "i")
    minStr = extractAfter(period, 1);
    minutes = str2double(minStr);
    if isnan(minutes) || minutes <= 0
        days = 30;
        return
    end
    barsPerDay = 24 * 60 / minutes;
    days = max(1, floor(43200 / barsPerDay));
    return
end
% Unknown period -> safest small chunk.
days = 7;
end

function nv = struct2nv(s)
fn = fieldnames(s);
nv = cell(1, 2 * numel(fn));
for k = 1:numel(fn)
    nv{2*k-1} = fn{k};
    nv{2*k}   = s.(fn{k});
end
end
