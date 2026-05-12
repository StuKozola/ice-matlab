classdef SymbolCache < handle
    %SymbolCache Wide symbol master joined from FTPCSD + FTPSEDOL [+ FTPCUSIP].
    %   Keyed by (srcId, ticker). Built from local FTP files and persisted
    %   under <cacheRoot>/symbology so downstream lookups don't repeatedly
    %   re-parse the source CSVs.
    %
    %   Two persistence layouts depending on build size:
    %
    %   * Small builds (<= PartitionedThreshold parts): one merged table is
    %     materialised in RAM, persisted as symbol_master.parquet, and
    %     served whole by table(). Keeps tests and small interactive rebuilds
    %     fast and ergonomic.
    %
    %   * Large builds (> PartitionedThreshold parts): every part is written
    %     to its own parquet file under symbology/parts/part_<srcId>.parquet
    %     and never materialised together in RAM. FTPSEDOL is cached as
    %     symbology/ftpsedol.parquet and joined lazily by lookup(). table()
    %     becomes a streaming read across the partitioned dataset and will
    %     refuse to materialise on builds known to exceed available RAM.
    %     This is the path the 311-source prod symbology takes; the
    %     materialised path used to OOM in setcats/vertcat.

    properties (SetAccess = immutable)
        Root (1,1) string
        PartitionedThreshold (1,1) double = 50
    end

    properties (Access = private)
        Tbl table
        Partitioned (1,1) logical = false
        SedolFileCached (1,1) string = ""
    end

    methods
        function obj = SymbolCache(cacheRoot)
            arguments
                cacheRoot (1,1) string = ""
            end
            if strlength(cacheRoot) == 0
                obj.Root = ice.config.cacheRoot();
            else
                obj.Root = ice.config.cacheRoot(cacheRoot);
            end
        end

        function summary = build(obj, opts)
            %BUILD Build the symbol master from local FTP files.
            %
            %   Returns a struct with .partitioned (logical), .nParts,
            %   .totalRows (estimated, scan-free for the partitioned path),
            %   .partsDir or .snapshotFile depending on mode.
            %
            %   Workers > 1 fans the read step out across a Processes pool.
            %   Each worker writes its part-table to its final parquet path
            %   under symbology/parts/ (large mode) or to a temp stage dir
            %   (small mode) and returns only the path. Returning full
            %   tables across parfeval blows the distcompserialize64 buffer
            %   at ~270/311 parts in practice; disk staging is bounded.
            arguments
                obj
                opts.FtpcsdFiles  (1,:) string = strings(0)
                opts.FtpsedolFile (1,1) string = ""
                opts.FtpcusipFile (1,1) string = ""
                opts.ShowProgress (1,1) logical = true
                opts.Workers (1,1) double {mustBePositive,mustBeInteger} = 2
            end

            nFiles = numel(opts.FtpcsdFiles);
            partitioned = nFiles > obj.PartitionedThreshold;
            obj.Partitioned = partitioned;

            symRoot = fullfile(obj.Root, "symbology");
            if ~isfolder(symRoot); mkdir(symRoot); end
            partsDir = fullfile(symRoot, "parts");

            useParallel = opts.Workers > 1 ...
                && license("test", "Distrib_Computing_Toolbox") ...
                && nFiles >= 8;

            if useParallel
                pool = gcp("nocreate");
                if isempty(pool)
                    try
                        parpool("Processes", opts.Workers);
                    catch err
                        warning("ice:sym:SymbolCache:NoPool", ...
                            "Could not start parallel pool, falling back to serial: %s", err.message);
                        useParallel = false;
                    end
                end
            end

            if partitioned
                summary = obj.buildPartitioned(opts, partsDir, useParallel);
                if strlength(opts.FtpsedolFile) > 0
                    obj.cacheFtpsedol(opts.FtpsedolFile, symRoot);
                end
                obj.SedolFileCached = opts.FtpsedolFile;
                obj.Tbl = table();  % do not materialise
            else
                csd = obj.buildMaterialised(opts, useParallel);
                if strlength(opts.FtpsedolFile) > 0
                    sed = ice.ftp.readFtpsedol(opts.FtpsedolFile);
                    csd = obj.mergeOnSrcTicker(csd, sed, "sedolFromSedolFile");
                end
                obj.Tbl = csd;
                obj.persistSnapshot();
                summary = struct( ...
                    "partitioned", false, ...
                    "nParts", nFiles, ...
                    "totalRows", height(csd), ...
                    "snapshotFile", fullfile(symRoot, "symbol_master.parquet"));
            end
        end

        function tbl = table(obj)
            if obj.Partitioned
                tbl = obj.readAllPartitions();
            else
                tbl = obj.Tbl;
            end
        end

        function row = lookup(obj, srcId, ticker)
            arguments
                obj
                srcId (1,1) uint32
                ticker (1,1) string
            end
            if obj.Partitioned
                row = obj.lookupPartitioned(srcId, ticker);
                return
            end
            if isempty(obj.Tbl)
                obj.loadSnapshotIfAvailable();
            end
            mask = obj.Tbl.srcId == srcId & obj.Tbl.ticker == ticker;
            row = obj.Tbl(mask, :);
        end

        function loadSnapshot(obj)
            % Switch this instance to the on-disk layout that currently
            % exists under <cacheRoot>/symbology. Partitioned layout wins if
            % both happen to be present (the partitioned manifest is the
            % canonical prod artifact).
            symRoot = fullfile(obj.Root, "symbology");
            if isfile(fullfile(symRoot, "manifest.json"))
                obj.Partitioned = true;
                obj.Tbl = table();
                return
            end
            obj.Partitioned = false;
            obj.loadSnapshotIfAvailable();
        end

        function n = partitionRowCount(obj)
            %PARTITIONROWCOUNT Sum of part row counts from the manifest.
            %   Cheap: reads the manifest, doesn't open parquet files.
            man = obj.readManifest();
            if isempty(man)
                n = NaN;
            else
                n = sum([man.rows]);
            end
        end
    end

    methods (Access = private)
        function out = mergeOnSrcTicker(~, left, right, sedolColName)
            left.ticker  = string(left.ticker);
            right.ticker = string(right.ticker);

            right.Properties.VariableNames{strcmp(right.Properties.VariableNames, "sedol")} = char(sedolColName);

            out = outerjoin(left, right, ...
                Keys=["srcId", "ticker"], MergeKeys=true);

            if ismember("sedol", string(out.Properties.VariableNames)) && ...
               ismember(sedolColName, string(out.Properties.VariableNames))
                cur = out.sedol;
                cur(strlength(cur) == 0 | ismissing(cur)) = ...
                    out.(sedolColName)(strlength(cur) == 0 | ismissing(cur));
                out.sedol = cur;
                out.(sedolColName) = [];
            end
        end

        function csd = buildMaterialised(obj, opts, useParallel)
            nFiles = numel(opts.FtpcsdFiles);
            if opts.ShowProgress && nFiles > 0
                label = sprintf("FTPCSD read (%s)", ...
                    ternary(useParallel, sprintf("%dw", opts.Workers), "serial"));
                bar = ice.util.Progress(nFiles, label);
            else
                bar = ice.util.Progress.empty;
            end

            files = opts.FtpcsdFiles;
            if useParallel
                stageDir = fullfile(obj.Root, "tmp", "symbol_build_" + ...
                    string(feature("getpid")) + "_" + ...
                    string(posixtime(datetime("now"))));
                if ~isfolder(stageDir); mkdir(stageDir); end
                stageCleanup = onCleanup(@() rmIfExists(stageDir)); %#ok<NASGU>

                pool = gcp("nocreate");
                futures(nFiles) = parallel.FevalFuture();
                for k = 1:nFiles
                    stagePath = fullfile(stageDir, sprintf("part_%05d.parquet", k));
                    futures(k) = parfeval(pool, @stageReadFtpcsd, 1, files(k), stagePath);
                end
                stagedPaths = strings(nFiles, 1);
                for j = 1:nFiles
                    [idx, partPath] = fetchNext(futures);
                    stagedPaths(idx) = partPath;
                    if ~isempty(bar); bar.tick(); end
                end
                if ~isempty(bar); bar.done(); end

                if opts.ShowProgress
                    fprintf("[load]      reading %d staged parquet parts back...\n", nFiles);
                end
                parts = cell(nFiles, 1);
                for k = 1:nFiles
                    parts{k} = parquetread(stagedPaths(k));
                    try; delete(stagedPaths(k)); catch; end %#ok<NOSEMI>
                end
            else
                parts = cell(nFiles, 1);
                for k = 1:nFiles
                    parts{k} = ice.ftp.readFtpcsd(files(k));
                    if ~isempty(bar); bar.tick(); end
                end
                if ~isempty(bar); bar.done(); end
            end

            if nFiles == 0
                csd = table();
                return
            end
            if opts.ShowProgress
                fprintf("[harmonize] aligning columns across %d parts...\n", nFiles);
            end
            parts = harmonizePartSchemas(parts);
            if opts.ShowProgress
                fprintf("[vertcat]   concatenating %d parts...\n", nFiles);
            end
            t0 = tic;
            csd = vertcat(parts{:});
            if opts.ShowProgress
                fprintf("[vertcat]   done in %.1fs; total rows: %d\n", ...
                    toc(t0), height(csd));
            end
        end

        function summary = buildPartitioned(obj, opts, partsDir, useParallel)
            nFiles = numel(opts.FtpcsdFiles);
            if ~isfolder(partsDir); mkdir(partsDir); end

            if opts.ShowProgress
                label = sprintf("FTPCSD read (%s)", ...
                    ternary(useParallel, sprintf("%dw", opts.Workers), "serial"));
                bar = ice.util.Progress(nFiles, label);
            else
                bar = ice.util.Progress.empty;
            end

            files = opts.FtpcsdFiles;
            writtenPaths = strings(nFiles, 1);
            srcIds = uint32(zeros(nFiles, 1));
            rowCounts = zeros(nFiles, 1);

            if useParallel
                pool = gcp("nocreate");
                futures(nFiles) = parallel.FevalFuture();
                for k = 1:nFiles
                    futures(k) = parfeval(pool, @partitionedReadAndWrite, 1, ...
                        files(k), partsDir);
                end
                for j = 1:nFiles
                    [idx, partInfo] = fetchNext(futures);
                    writtenPaths(idx) = partInfo.path;
                    srcIds(idx) = partInfo.srcId;
                    rowCounts(idx) = partInfo.rows;
                    if ~isempty(bar); bar.tick(); end
                end
            else
                for k = 1:nFiles
                    partInfo = partitionedReadAndWrite(files(k), partsDir);
                    writtenPaths(k) = partInfo.path;
                    srcIds(k) = partInfo.srcId;
                    rowCounts(k) = partInfo.rows;
                    if ~isempty(bar); bar.tick(); end
                end
            end
            if ~isempty(bar); bar.done(); end

            mArr = struct("srcId", {}, "rows", {}, "file", {});
            for k = 1:nFiles
                [~, fname, fext] = fileparts(writtenPaths(k));
                mArr(end+1) = struct( ...
                    "srcId", srcIds(k), ...
                    "rows", rowCounts(k), ...
                    "file", char(fname + fext)); %#ok<AGROW>
            end
            obj.writeManifest(mArr);

            summary = struct( ...
                "partitioned", true, ...
                "nParts", nFiles, ...
                "totalRows", sum(rowCounts), ...
                "partsDir", partsDir);
        end

        function cacheFtpsedol(~, sedolFile, symRoot)
            sed = ice.ftp.readFtpsedol(sedolFile);
            parquetwrite(fullfile(symRoot, "ftpsedol.parquet"), sed);
        end

        function row = lookupPartitioned(obj, srcId, ticker)
            partFile = fullfile(obj.Root, "symbology", "parts", ...
                sprintf("part_%05d.parquet", srcId));
            if ~isfile(partFile)
                row = table();
                return
            end
            part = parquetread(partFile);
            if ~ismember("ticker", string(part.Properties.VariableNames))
                row = table();
                return
            end
            mask = string(part.ticker) == ticker;
            row = part(mask, :);
            if isempty(row); return; end

            % FTPSEDOL enrichment: only consider SEDOL rows with the same
            % (srcId, ticker). Loading the full 10M-row FTPSEDOL and
            % outerjoining drags in every unmatched SEDOL row.
            sedFile = fullfile(obj.Root, "symbology", "ftpsedol.parquet");
            if ~isfile(sedFile); return; end
            sed = parquetread(sedFile);
            sedMask = sed.srcId == srcId & string(sed.ticker) == ticker;
            sedSlice = sed(sedMask, :);
            if isempty(sedSlice); return; end
            row = obj.mergeOnSrcTicker(row, sedSlice, "sedolFromSedolFile");
        end

        function tbl = readAllPartitions(obj)
            partsDir = fullfile(obj.Root, "symbology", "parts");
            if ~isfolder(partsDir)
                tbl = table();
                return
            end
            d = dir(fullfile(partsDir, "part_*.parquet"));
            if isempty(d)
                tbl = table();
                return
            end
            % Read each, harmonise, vertcat. Will OOM on prod-scale builds —
            % callers at scale must use lookup() instead.
            parts = cell(numel(d), 1);
            for k = 1:numel(d)
                parts{k} = parquetread(fullfile(d(k).folder, d(k).name));
            end
            parts = harmonizePartSchemas(parts);
            tbl = vertcat(parts{:});
            % Apply on-the-fly FTPSEDOL join to mirror small-mode behaviour.
            sedFile = fullfile(obj.Root, "symbology", "ftpsedol.parquet");
            if isfile(sedFile)
                sed = parquetread(sedFile);
                tbl = obj.mergeOnSrcTicker(tbl, sed, "sedolFromSedolFile");
            end
        end

        function persistSnapshot(obj)
            dir = fullfile(obj.Root, "symbology");
            if ~isfolder(dir); mkdir(dir); end
            parquetwrite(fullfile(dir, "symbol_master.parquet"), obj.Tbl);
        end

        function loadSnapshotIfAvailable(obj)
            file = fullfile(obj.Root, "symbology", "symbol_master.parquet");
            if isfile(file)
                obj.Tbl = parquetread(file);
            end
        end

        function writeManifest(obj, manArr)
            % Persist the partition manifest as JSON so totalRows is
            % O(parts) to compute without opening any parquet.
            file = fullfile(obj.Root, "symbology", "manifest.json");
            fid = fopen(file, "w", "n", "UTF-8");
            if fid == -1
                error("ice:sym:SymbolCache:ManifestWriteFailed", ...
                    "Could not open %s for write", file);
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, "%s", jsonencode(manArr));
        end

        function man = readManifest(obj)
            file = fullfile(obj.Root, "symbology", "manifest.json");
            if ~isfile(file)
                man = struct("srcId", {}, "rows", {}, "file", {});
                return
            end
            man = jsondecode(fileread(file));
        end
    end
end

function v = ternary(cond, a, b)
if cond; v = a; else; v = b; end
end

function outPath = stageReadFtpcsd(filePath, stagePath)
% Worker entry point (small-mode): read one FTPCSD CSV and stage as parquet.
tbl = ice.ftp.readFtpcsd(filePath);
parquetwrite(stagePath, tbl);
outPath = stagePath;
end

function info = partitionedReadAndWrite(filePath, partsDir)
% Worker entry point (large-mode): read one FTPCSD CSV, write the part
% parquet into its final location keyed by srcId, return a small struct
% describing the part. No table data crosses parfeval.
tbl = ice.ftp.readFtpcsd(filePath);

if ismember("srcId", string(tbl.Properties.VariableNames)) && height(tbl) > 0
    s = tbl.srcId(1);
    if iscategorical(s); s = uint32(str2double(string(s))); end
    srcId = uint32(s);
else
    % Fallback: derive srcId from filename (FTPCSD_PUB1_<srcId>_<date>.csv.bz2).
    [~, base] = fileparts(filePath);
    tokens = split(string(base), "_");
    srcId = uint32(0);
    for k = 1:numel(tokens)
        n = str2double(tokens(k));
        if ~isnan(n) && n < 1e9 && n > 0 && n ~= round(n / 1e6) * 1e6
            srcId = uint32(n);
            break
        end
    end
end

outPath = fullfile(partsDir, sprintf("part_%05d.parquet", srcId));
tmpPath = outPath + ".tmp." + string(feature("getpid"));
parquetwrite(tmpPath, tbl);
[ok, msg] = movefile(tmpPath, outPath, "f");
if ~ok
    error("ice:sym:SymbolCache:RenameFailed", ...
        "Could not rename %s -> %s : %s", tmpPath, outPath, msg);
end

info = struct("srcId", srcId, "rows", height(tbl), "path", outPath);
end

function rmIfExists(d)
if isfolder(d)
    try; rmdir(d, "s"); catch; end %#ok<NOSEMI>
end
end

function parts = harmonizePartSchemas(parts)
allCols = string([]);
colType = containers.Map('KeyType','char','ValueType','char');
for k = 1:numel(parts)
    vn = string(parts{k}.Properties.VariableNames);
    for j = 1:numel(vn)
        if ~colType.isKey(char(vn(j)))
            colType(char(vn(j))) = class(parts{k}.(vn(j)));
            allCols(end+1) = vn(j); %#ok<AGROW>
        end
    end
end

for k = 1:numel(parts)
    p = parts{k};
    have = string(p.Properties.VariableNames);
    missingCols = setdiff(allCols, have, "stable");
    for c = 1:numel(missingCols)
        name = missingCols(c);
        n = height(p);
        switch colType(char(name))
            case "categorical"
                p.(name) = categorical(strings(n, 1));
                p.(name)(:) = missing;
            case "string"
                col = strings(n, 1);
                col(:) = missing;
                p.(name) = col;
            case {"double", "single"}
                p.(name) = nan(n, 1);
            case {"uint8","uint16","uint32","uint64","int8","int16","int32","int64"}
                p.(name) = zeros(n, 1, colType(char(name)));
            case "datetime"
                p.(name) = NaT(n, 1);
            case "logical"
                p.(name) = false(n, 1);
            otherwise
                col = strings(n, 1);
                col(:) = missing;
                p.(name) = col;
        end
    end
    parts{k} = p(:, allCols);
end

for c = 1:numel(allCols)
    name = allCols(c);
    if ~strcmp(colType(char(name)), "categorical"); continue; end
    cats = string([]);
    for k = 1:numel(parts)
        if iscategorical(parts{k}.(name))
            cats = unique([cats; string(categories(parts{k}.(name)))]); %#ok<AGROW>
        end
    end
    for k = 1:numel(parts)
        col = parts{k}.(name);
        if ~iscategorical(col)
            col = categorical(string(col), cats);
        else
            col = setcats(col, cellstr(cats));
        end
        parts{k}.(name) = col;
    end
end
end
