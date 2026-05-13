%[text] # Parallel History Backfill
%[text] Demonstrates `ice.jobs.backfillHistory` — the non-interactive job that pulls daily or intraday history for a basket of symbols in parallel via `parfeval` and persists results as partitioned parquet under `<cacheRoot>/parquet/history/symbol=<sym>/`.
%[text] Key properties:
%[text] - Idempotent. Symbols already on disk for the requested window are skipped unless `Force=true`.
%[text] - Per-symbol failures don't abort the basket. `summary.failedSymbols` lists them.
%[text] - Workers share ICE's 20-in-flight / 20-req-sec ceiling by each running with `RateLimiter(MaxConcurrent=20/N, MaxPerSecond=20/N)`. Defaults to N=4.
%[text] - Dispatches to `/xhist` (daily/weekly/monthly) when `BarInterval` is "daily" etc, and to `/xtick` with auto-chunking when `BarInterval` is "t" or "i&lt;N&gt;". \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Backfill 5 years of daily bars for a small basket
%[text] First run downloads. Re-running with the same parameters is essentially free (skip path).
basket = ["AAPL","MSFT","GOOG","IBM","NVDA"];
summary = ice.jobs.backfillHistory(basket, ...
    StartDate=datetime(2020,1,1), EndDate=datetime(2024,12,31), ...
    BarInterval="daily", Workers=2);
disp(summary)

%%
%[text] ## Read one back from disk
%[text] Each symbol lives at `<cacheRoot>/parquet/history/symbol=<sym>/<from>-<to>.parquet`.
cacheRoot = ice.config.cacheRoot();
aapl = parquetread(fullfile(cacheRoot, "parquet", "history", "symbol=AAPL", "20200101-20241231.parquet"));
fprintf("AAPL parquet: %d rows, %d cols\n", height(aapl), width(aapl))
disp(head(aapl, 3))

%%
%[text] ## Plot the basket together
%[text] Read all 5 symbols, normalise each to 100 at the start, and overlay.
figure("Visible","on");
hold on;
for sym = basket
    fn = fullfile(cacheRoot, "parquet", "history", "symbol=" + sym, "20200101-20241231.parquet");
    if isfile(fn)
        t = parquetread(fn);
        t = sortrows(t, "when");
        plot(t.when, 100 * t.close / t.close(1), "DisplayName", sym);
    end
end
hold off;
xlabel("Date"); ylabel("Normalised close (start=100)");
title("Daily close, normalised 2020–2024");
legend("show", "Location", "northwest");
grid on;

%%
%[text] ## Intraday flavour
%[text] The same job pulls intraday bars when `BarInterval` is e.g. `"i5"`. Output filenames carry the `yyyymmdd-yyyymmdd` window so daily and intraday backfills don't clash.
endD = datetime("now", TimeZone="UTC");
startD = endD - days(7);
intraSummary = ice.jobs.backfillHistory(["AAPL","MSFT"], ...
    StartDate=startD, EndDate=endD, ...
    BarInterval="i5", Workers=2);
disp(intraSummary)
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
