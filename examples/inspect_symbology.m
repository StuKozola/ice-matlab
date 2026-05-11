%[text] # Inspect the ICE Symbol Master
%[text] After the first successful `ice.jobs.syncDailySymbology()` run there should be a `symbol_master.parquet` snapshot under `<cacheRoot>/symbology/`. This Live Script loads it and shows a few sanity checks against your live data.
%[text] No network access — operates entirely on the cached files. \
addpath(fileparts(fileparts(mfilename("fullpath"))));

%%
%[text] ## Load the cached snapshot
sym = ice.sym.SymbolCache();
sym.loadSnapshot();
master = sym.table();
fprintf("Rows: %d\n", height(master))
fprintf("Cols: %d\n", width(master))
fprintf("Columns: %s\n", strjoin(string(master.Properties.VariableNames), ", "))

%%
%[text] ## Source-ID coverage
%[text] How many distinct exchanges (source IDs) made it into the master, and how many rows per source?
srcCounts = groupsummary(master, "srcId");
srcCounts = sortrows(srcCounts, "GroupCount", "descend");
fprintf("Distinct source IDs: %d\n", height(srcCounts))
head(srcCounts, 15)

%%
%[text] ## SEDOL coverage
hasSedol = strlength(master.sedol) > 0 & ~ismissing(master.sedol);
fprintf("Rows with SEDOL populated: %d (%.1f%%)\n", ...
    sum(hasSedol), 100 * sum(hasSedol) / height(master))

%%
%[text] ## Currency mix (top 10)
ccyTab = groupsummary(master, "currency");
ccyTab = sortrows(ccyTab, "GroupCount", "descend");
head(ccyTab, 10)

%%
%[text] ## Lookup example
%[text] Single-row lookup for a known equity. Adjust to a symbol that exists in your subscription.
candidates = ["AAPL", "MSFT", "GOOG", "IBM"];
for sym = candidates
    rows = master(master.ticker == sym, :);
    if height(rows) > 0
        fprintf("%-6s -> %d row(s); first match srcId=%d sedol=%s isin=%s\n", ...
            sym, height(rows), rows.srcId(1), rows.sedol(1), rows.isin(1));
    else
        fprintf("%-6s -> not found\n", sym);
    end
end
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
