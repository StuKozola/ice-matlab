%[text] # Inspect the ICE Symbol Master
%[text] After the first successful `ice.jobs.syncDailySymbology()` run there is a cached symbology dataset under `<cacheRoot>/symbology/`. This script reads it and shows a few sanity checks.
%[text] Two on-disk layouts are possible:
%[text] - **Small** (≤ 50 sources): single `symbol_master.parquet` snapshot. `sym.table()` returns the whole thing.
%[text] - **Large** (the prod 311-source case): partitioned `parts/part_<srcId>.parquet` files plus `manifest.json`. Calling `sym.table()` would re-materialise ~23 M rows in memory — avoid it. This script reads the manifest for coverage stats and uses `sym.lookup()` for per-symbol probes. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the cache
sym = ice.sym.SymbolCache();
sym.loadSnapshot();

%%
%[text] ## Detect layout
manifestPath = fullfile(sym.Root, "symbology", "manifest.json");
isPartitioned = isfile(manifestPath);
if isPartitioned
    fprintf("Layout: partitioned (manifest at %s)\n", manifestPath);
else
    fprintf("Layout: single-file snapshot\n");
end

%%
%[text] ## Coverage stats
%[text] For the partitioned layout we read the manifest — O(parts), never opens a parquet. For the small layout we summarise the in-memory table.
if isPartitioned
    man = jsondecode(fileread(manifestPath));
    rowCounts = double([man.rows]);
    srcIds = uint32([man.srcId]);
    fprintf("Partitions: %d   total rows: %d\n", numel(man), sum(rowCounts));
    [~, hi] = max(rowCounts);
    [~, lo] = min(rowCounts);
    fprintf("Largest source: srcId=%d with %d rows\n", srcIds(hi), rowCounts(hi));
    fprintf("Smallest source: srcId=%d with %d rows\n", srcIds(lo), rowCounts(lo));
    cov = table(srcIds(:), rowCounts(:), VariableNames=["srcId","rows"]);
    cov = sortrows(cov, "rows", "descend");
    disp(head(cov, 10))
else
    master = sym.table();
    fprintf("Rows: %d  Cols: %d\n", height(master), width(master));
    fprintf("Columns: %s\n", strjoin(string(master.Properties.VariableNames), ", "));
end

%%
%[text] ## Per-symbol lookups
%[text] `sym.lookup(srcId, ticker)` reads only the relevant partition file plus a filtered FTPSEDOL slice. Sub-second regardless of total dataset size.
%[text] Each (srcId, ticker) is unique — the SAME ticker on NYSE vs NASDAQ vs Toronto is a different (srcId, ticker) pair. The script probes the common US equity sources: NYSE (558), NASDAQ (564), NYSE Arca (562), BATS (596), plus the top-3 largest sources as fallback.
candidates = ["AAPL", "MSFT", "GOOG", "IBM"];
if isPartitioned
    knownEquitySrcs = uint32([558, 564, 562, 596]);   % NYSE, NASDAQ, ARCA, BATS
    topSrcs = cov.srcId(1:min(3, height(cov)));
    probeSrcs = unique([knownEquitySrcs(:); topSrcs(:)], "stable");
    for k = 1:numel(candidates)
        tk = candidates(k);
        found = false;
        for s = probeSrcs.'
            row = sym.lookup(s, tk);
            if height(row) > 0
                fprintf("%-6s -> srcId=%d sedol=%s isin=%s\n", ...
                    tk, s, fmtMissing(row.sedol(1)), fmtMissing(row.isin(1)));
                found = true;
                break;
            end
        end
        if ~found
            fprintf("%-6s -> not found in any probed source\n", tk);
        end
    end
else
    master = sym.table();
    for k = 1:numel(candidates)
        tk = candidates(k);
        rows = master(master.ticker == tk, :);
        if height(rows) > 0
            fprintf("%-6s -> %d row(s); first srcId=%d sedol=%s\n", ...
                tk, height(rows), rows.srcId(1), fmtMissing(rows.sedol(1)));
        else
            fprintf("%-6s -> not found\n", tk);
        end
    end
end
%[text]

function s = fmtMissing(v)
s = string(v);
if ismissing(s) || strlength(s) == 0; s = "<missing>"; end
end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
