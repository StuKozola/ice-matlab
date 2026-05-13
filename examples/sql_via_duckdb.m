%[text] # SQL over the ICE cache via DuckDB
%[text] DuckDB ships with **MATLAB R2026a+ Database Toolbox** (`duckdb()` function). On R2026a or newer this script opens a DuckDB connection wired up to the cached symbology and history parquets, then runs analytic SQL queries over them — no full-table materialisation in MATLAB.
%[text] On older MATLAB releases the helper raises `ice:io:toDuckdb:Unsupported`. The script catches that and prints a guidance message instead of failing. You can still run the same queries against the parquet datasets from the standalone DuckDB CLI or Python.
%[text] What this demonstrates:
%[text] - Auto-registered views: `symbology_master`, `symbology_sedol`, `history_daily`.
%[text] - Hive-partitioned pushdown on `history_daily WHERE symbol = '...'`.
%[text] - DuckDB cross-source joins (symbol → SEDOL) at engine speed. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the connection
%[text] In-memory (default) — no file persisted. Add `File="ice.duckdb"` to materialise it.
try
    conn = ice.io.toDuckdb();
catch err
    if err.identifier == "ice:io:toDuckdb:Unsupported"
        fprintf("\n%s\n\n", err.message);
        fprintf("Skipping the rest of the script. Re-run on R2026a+ to see the queries execute.\n");
        return
    end
    rethrow(err);
end
cleanup = onCleanup(@() close(conn));
fprintf("DuckDB connection: open=%d\n", isopen(conn))

%%
%[text] ## Inventory the views
%[text] `information_schema.tables` reports every view we registered against the cache.
views = fetch(conn, "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = 'main' ORDER BY table_name");
disp(views)

%%
%[text] ## Symbology coverage by source
%[text] Count rows per `srcId` to see which exchanges dominate the symbol master. The query never materialises the 23M-row union in MATLAB — DuckDB streams.
top = fetch(conn, "SELECT srcId, COUNT(*) AS rows FROM symbology_master GROUP BY srcId ORDER BY rows DESC LIMIT 10");
disp(top)

%%
%[text] ## Symbol → SEDOL lookup via SQL
%[text] DuckDB joins the partitioned symbology master against the standalone FTPSEDOL view in one query. Push-down predicates make this sub-second even though the underlying datasets are tens of millions of rows.
lookup = fetch(conn, [
    "SELECT m.srcId, m.ticker, m.sedol AS sedol_from_master, s.sedol AS sedol_from_sedol_file "
    "FROM symbology_master m "
    "LEFT JOIN symbology_sedol s ON m.srcId = s.srcId AND m.ticker = s.ticker "
    "WHERE m.ticker IN ('AAPL','MSFT','GOOG','IBM') AND m.srcId IN (558, 564) "
    "ORDER BY m.ticker, m.srcId"]);
disp(lookup)

%%
%[text] ## History summary by symbol
%[text] If you've run the `backfill_history` example, the partitioned history parquets show up under the `history_daily` view. Hive partitioning lets DuckDB read only the relevant `symbol=<sym>/` subdirectory when the filter is on `symbol`.
hist = fetch(conn, "SELECT symbol, COUNT(*) AS bars, MIN(when) AS first_bar, MAX(when) AS last_bar FROM history_daily GROUP BY symbol ORDER BY symbol");
disp(hist)
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
