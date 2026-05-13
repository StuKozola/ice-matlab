function conn = toDuckdb(opts)
%TODUCKDB Open a DuckDB connection wired up to the ICE cache parquet datasets.
%   conn = ice.io.toDuckdb()
%       opens an in-memory DuckDB, registers views over the cached
%       symbology and history parquets, and returns the open connection.
%       Caller is responsible for close(conn).
%
%   conn = ice.io.toDuckdb(File="ice.duckdb")
%       opens (or creates) a persistent DuckDB file at that path. The
%       cache views are re-created idempotently so a stale file from a
%       previous build is safe to reuse.
%
%   Views created (when the underlying parquet exists):
%     symbology_master  — partitioned <cacheRoot>/symbology/parts/part_*.parquet
%     symbology_sedol   — <cacheRoot>/symbology/ftpsedol.parquet (if present)
%     history_daily     — <cacheRoot>/parquet/history/symbol=*/*.parquet
%
%   Requires MATLAB R2026a+ with Database Toolbox (duckdb() shipped in
%   R2026a). On older releases ice.io.toDuckdb errors with a typed
%   exception explaining the requirement.
%
%   Example:
%       conn = ice.io.toDuckdb();
%       t = fetch(conn, "SELECT symbol, COUNT(*) AS n FROM history_daily " + ...
%                       "GROUP BY symbol ORDER BY n DESC");
%       close(conn);

arguments
    opts.File (1,1) string = ""
    opts.CacheRoot (1,1) string = ""
end

if exist("duckdb", "file") ~= 2
    error("ice:io:toDuckdb:Unsupported", ...
        ['duckdb() is not available in this MATLAB release. ', ...
         'Database Toolbox ships DuckDB starting in R2026a. ', ...
         'You are on %s. Upgrade MATLAB or query the parquet ', ...
         'datasets from the duckdb CLI / Python instead.'], string(version("-release")));
end

if strlength(opts.CacheRoot) == 0
    cacheRoot = ice.config.cacheRoot();
else
    cacheRoot = opts.CacheRoot;
end

if strlength(opts.File) == 0
    conn = duckdb();
else
    conn = duckdb(char(opts.File));
end

% View 1: partitioned symbology master.
partsGlob = fullfile(cacheRoot, "symbology", "parts", "part_*.parquet");
if hasAnyMatch(partsGlob)
    execute(conn, sprintf( ...
        "CREATE OR REPLACE VIEW symbology_master AS SELECT * FROM read_parquet('%s')", ...
        sqlEscape(partsGlob)));
elseif isfile(fullfile(cacheRoot, "symbology", "symbol_master.parquet"))
    execute(conn, sprintf( ...
        "CREATE OR REPLACE VIEW symbology_master AS SELECT * FROM read_parquet('%s')", ...
        sqlEscape(fullfile(cacheRoot, "symbology", "symbol_master.parquet"))));
end

% View 2: standalone FTPSEDOL cache.
sedolFile = fullfile(cacheRoot, "symbology", "ftpsedol.parquet");
if isfile(sedolFile)
    execute(conn, sprintf( ...
        "CREATE OR REPLACE VIEW symbology_sedol AS SELECT * FROM read_parquet('%s')", ...
        sqlEscape(sedolFile)));
end

% View 3: partitioned history. The hive-style symbol=<sym>/ layout lets
% DuckDB push down a WHERE symbol = '...' filter cheaply.
historyGlob = fullfile(cacheRoot, "parquet", "history", "symbol=*", "*.parquet");
if hasAnyMatch(historyGlob)
    execute(conn, sprintf( ...
        "CREATE OR REPLACE VIEW history_daily AS SELECT * FROM read_parquet('%s', hive_partitioning=true)", ...
        sqlEscape(historyGlob)));
end
end

function tf = hasAnyMatch(globPattern)
% True when at least one file matches the glob (cross-OS dir wrapper).
[parent, name, ext] = fileparts(globPattern);
d = dir(fullfile(parent, name + ext));
tf = ~isempty(d);
end

function out = sqlEscape(s)
% DuckDB SQL string literal escaping: single-quote becomes ''.
out = strrep(string(s), "'", "''");
end
