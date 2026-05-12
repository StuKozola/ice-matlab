function summary = backfillHistory(symbols, opts)
%BACKFILLHISTORY Parallel daily-history back-fill for a basket of symbols.
%
%   summary = ice.jobs.backfillHistory(["AAPL","MSFT","GOOG"], ...
%       StartDate=datetime(2020,1,1), EndDate=datetime(2024,12,31))
%
%   Calls ice.api.history per symbol via parfeval, writes one parquet
%   file per symbol to <cacheRoot>/parquet/history/symbol=<sym>/<from>-<to>.parquet.
%   Skips symbols whose target file already exists (override with Force=true).
%
%   Workers share the ICE 20-req/s budget by each running with a
%   per-worker RateLimiter sized 20/Nworkers. RateLimiter is a handle
%   class so cross-worker state isn't shared; per-worker scaling gives
%   the same global cap without inter-process coordination.
%
%   Emits structured log events: backfill_start, backfill_skip,
%   backfill_symbol_ok, backfill_symbol_failed, backfill_done. Failures
%   on individual symbols don't abort the job; the summary lists them.

arguments
    symbols (1,:) string
    opts.StartDate datetime = NaT
    opts.EndDate datetime = NaT
    opts.BarInterval (1,1) string = "daily"
    opts.Currency (1,1) string = ""
    opts.Workers (1,1) double {mustBePositive,mustBeInteger} = 4
    opts.Force (1,1) logical = false
    opts.ShowProgress (1,1) logical = true
    opts.SessionFactory function_handle = function_handle.empty
end

started = datetime("now");
ice.util.log("backfill_start", struct( ...
    "symbols", numel(symbols), ...
    "startDate", string(opts.StartDate), ...
    "endDate", string(opts.EndDate), ...
    "barInterval", opts.BarInterval, ...
    "workers", opts.Workers, ...
    "force", opts.Force));

cacheRoot = ice.config.cacheRoot();
histRoot = fullfile(cacheRoot, "parquet", "history");
if ~isfolder(histRoot); mkdir(histRoot); end

% Plan: figure out target file path per symbol and which ones to fetch.
targets = strings(numel(symbols), 1);
toFetch = false(numel(symbols), 1);
for k = 1:numel(symbols)
    symDir = fullfile(histRoot, "symbol=" + sanitizeSymbol(symbols(k)));
    if ~isfolder(symDir); mkdir(symDir); end
    targets(k) = fullfile(symDir, dateLabel(opts.StartDate, opts.EndDate) + ".parquet");
    toFetch(k) = opts.Force || ~isfile(targets(k));
end
nSkip = sum(~toFetch);
if nSkip > 0
    ice.util.log("backfill_skip", struct("skipped", nSkip));
end

% Resolve credentials on the client; pass them to workers explicitly so
% they don't depend on each worker's Vault visibility.
user = ice.config.credentials("ICE_API_USER");
pwd  = ice.config.credentials("ICE_API_PWD");

fetchIdx = find(toFetch);
nFetch = numel(fetchIdx);
results = repmat(struct("symbol","","rows",0,"ok",false,"error",""), nFetch, 1);

if nFetch == 0
    summary = makeSummary(symbols, targets, results, nSkip, started);
    ice.util.log("backfill_done", summary);
    return
end

useParallel = opts.Workers > 1 ...
    && license("test", "Distrib_Computing_Toolbox") ...
    && nFetch >= 2;

if useParallel
    pool = gcp("nocreate");
    if isempty(pool)
        try
            parpool("Processes", opts.Workers);
        catch err
            warning("ice:jobs:backfillHistory:NoPool", ...
                "Could not start parallel pool, falling back to serial: %s", err.message);
            useParallel = false;
        end
    end
end

% Per-worker concurrency and rate budgets. With ICE's 20 in flight /
% 20 per second cap, splitting evenly across workers keeps total under
% the cap while letting each worker make forward progress.
nWorkers = opts.Workers;
perWorkerConcurrent = max(1, floor(20 / nWorkers));
perWorkerPerSecond  = max(1, floor(20 / nWorkers));

if opts.ShowProgress && nFetch > 0
    label = sprintf("backfill (%s)", ...
        ternary(useParallel, sprintf("%dw", nWorkers), "serial"));
    bar = ice.util.Progress(nFetch, label);
else
    bar = ice.util.Progress.empty;
end

if useParallel
    pool = gcp("nocreate");
    futures(nFetch) = parallel.FevalFuture();
    for j = 1:nFetch
        k = fetchIdx(j);
        futures(j) = parfeval(pool, @workerFetchOne, 1, ...
            symbols(k), targets(k), opts.StartDate, opts.EndDate, ...
            opts.BarInterval, opts.Currency, ...
            user, pwd, perWorkerConcurrent, perWorkerPerSecond);
    end
    for j = 1:nFetch
        [idx, r] = fetchNext(futures);
        results(idx) = r;
        if ~isempty(bar); bar.tick(); end
        if r.ok
            ice.util.log("backfill_symbol_ok", struct( ...
                "symbol", r.symbol, "rows", r.rows));
        else
            ice.util.log("backfill_symbol_failed", struct( ...
                "symbol", r.symbol, "error", r.error), Level="warn");
        end
    end
else
    for j = 1:nFetch
        k = fetchIdx(j);
        results(j) = workerFetchOne(symbols(k), targets(k), ...
            opts.StartDate, opts.EndDate, opts.BarInterval, opts.Currency, ...
            user, pwd, 8, 8);
        if ~isempty(bar); bar.tick(); end
        if results(j).ok
            ice.util.log("backfill_symbol_ok", struct( ...
                "symbol", results(j).symbol, "rows", results(j).rows));
        else
            ice.util.log("backfill_symbol_failed", struct( ...
                "symbol", results(j).symbol, "error", results(j).error), Level="warn");
        end
    end
end
if ~isempty(bar); bar.done(); end

summary = makeSummary(symbols, targets, results, nSkip, started);
ice.util.log("backfill_done", summary);
end

% --------------------------------------------------------------------------

function r = workerFetchOne(symbol, target, startDate, endDate, ...
        barInterval, currency, user, pwd, maxConcurrent, maxPerSecond)
% Worker entry point: build a Session, fetch one symbol, write parquet.
% Dispatches to /xhist (daily+) or /xtick with chunked windowing
% (intraday) based on barInterval.
r = struct("symbol", symbol, "rows", 0, "ok", false, "error", "");
try
    sess = ice.api.Session(Username=user, Password=pwd, ...
        MaxConcurrent=maxConcurrent, MaxPerSecond=maxPerSecond);
    if isIntradayInterval(barInterval)
        if isnat(startDate) || isnat(endDate)
            r.error = "intraday backfill requires StartDate and EndDate";
            return
        end
        tt = ice.api.intradayHistoryRange(sess, symbol, startDate, endDate, ...
            Period=barInterval);
    else
        histOpts = struct( ...
            "StartDate", startDate, ...
            "EndDate", endDate, ...
            "BarInterval", barInterval);
        if strlength(currency) > 0
            histOpts.Currency = currency;
        end
        nv = struct2nv(histOpts);
        tt = ice.api.history(sess, symbol, nv{:});
    end
    if isempty(tt) || height(tt) == 0
        r.error = "no rows returned";
        return
    end
    out = timetable2table(tt);
    parquetwrite(target, out);
    r.rows = height(out);
    r.ok = true;
catch err
    r.error = string(err.message);
end
end

function tf = isIntradayInterval(barInterval)
% /xtick periods: "t" (tick), "i<minutes>" (intraday bars).
% Everything else goes through /xhist.
b = lower(barInterval);
tf = b == "t" || startsWith(b, "i");
end

function nv = struct2nv(s)
% Convert a scalar struct into a name-value cell suitable for splatting
% into a function with name-value arguments.
fn = fieldnames(s);
nv = cell(1, 2 * numel(fn));
for k = 1:numel(fn)
    nv{2*k-1} = fn{k};
    nv{2*k}   = s.(fn{k});
end
end

function summary = makeSummary(symbols, targets, results, nSkip, started)
elapsed = datetime("now") - started;
okMask = false(numel(results), 1);
for k = 1:numel(results); okMask(k) = results(k).ok; end
nOk = sum(okMask);
nFail = sum(~okMask & arrayfun(@(r) strlength(r.symbol) > 0, results));
failed = strings(0, 1);
for k = 1:numel(results)
    if ~results(k).ok && strlength(results(k).symbol) > 0
        failed(end+1) = results(k).symbol; %#ok<AGROW>
    end
end
summary = struct( ...
    "symbolsRequested", numel(symbols), ...
    "skipped", nSkip, ...
    "ok", nOk, ...
    "failed", nFail, ...
    "failedSymbols", failed, ...
    "outputs", targets, ...
    "elapsedSeconds", seconds(elapsed));
end

function s = sanitizeSymbol(sym)
% File-system-safe symbol: replace path-hostile chars with '_'.
s = regexprep(sym, '[\\/:*?"<>| ]', "_");
end

function s = dateLabel(d1, d2)
% Range label for the output filename. NaT becomes "none".
s1 = ternaryStr(isnat(d1), "none", string(d1, "yyyyMMdd"));
s2 = ternaryStr(isnat(d2), "none", string(d2, "yyyyMMdd"));
s = s1 + "-" + s2;
end

function v = ternary(cond, a, b)
if cond; v = a; else; v = b; end
end

function v = ternaryStr(cond, a, b)
if cond; v = a; else; v = b; end
end
