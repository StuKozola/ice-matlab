%[text] # Intraday History — AAPL minute bars
%[text] Pulls intraday bars from `/xtick` for a single symbol. Two interfaces:
%[text] - `ice.api.intradayHistory(...)` — one request, capped at 43,200 bars per ICE limits.
%[text] - `ice.api.intradayHistoryRange(...)` — slices a longer window into chunks under the cap and stitches results together with boundary dedup.
%[text] Prerequisites:
%[text] - `ice.config.setupVault()` populated with `ICE_API_USER` / `ICE_API_PWD`.
%[text] - Intraday history retention varies by subscription (~90 days on this account). Queries outside the retention window come back as an empty `<xtick>` envelope, not an error. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the API session
session = ice.api.Session();

%%
%[text] ## Recent 5-minute bars (single request)
%[text] Last 50 five-minute bars for AAPL.
tt = ice.api.intradayHistory(session, "AAPL", Period="i5", NBars=50);
fprintf("Returned %d bars; window %s .. %s\n", height(tt), tt.Properties.RowTimes(1), tt.Properties.RowTimes(end))
disp(head(tt, 5))

%%
%[text] ## Multi-day backfill with auto-chunking
%[text] Pulling 60 days of 1-minute bars (~16k rows) exceeds the 43,200-bar cap in extreme cases but is well inside it for AAPL's ~390-bar US-cash-session day. The range wrapper auto-slices into 30-day chunks for `i1`.
endD = datetime("now", TimeZone="UTC");
startD = endD - days(60);
t0 = tic;
bars = ice.api.intradayHistoryRange(session, "AAPL", startD, endD, Period="i1");
fprintf("Pulled %d minute-bars across 60 days in %.1fs\n", height(bars), toc(t0))

%%
%[text] ## Sanity: timestamps are unique and sorted
rt = bars.Properties.RowTimes;
assert(numel(rt) == numel(unique(rt)), "duplicate timestamps after dedup");
assert(issorted(rt), "timestamps not sorted");
fprintf("Time range: %s .. %s (%d distinct timestamps)\n", ...
    rt(1), rt(end), numel(unique(rt)));

%%
%[text] ## Daily volume profile
%[text] Aggregate minute-volume by minute-of-day to see the U-shaped intraday liquidity profile. Times come back in UTC; convert to US/Eastern for a more readable x-axis if you trade US hours.
barsET = bars;
barsET.Properties.RowTimes.TimeZone = "America/New_York";
minuteOfDay = hour(barsET.Properties.RowTimes) * 60 + minute(barsET.Properties.RowTimes);
volByMinute = accumarray(minuteOfDay + 1, barsET.volume, [], @sum);
figure("Visible","on");
plot((0:numel(volByMinute)-1)/60, volByMinute, "-");
xlabel("Hour of day (US/Eastern)"); ylabel("Total volume across 60 days");
title("AAPL 1-minute volume profile");
xlim([0 24]); grid on;
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
