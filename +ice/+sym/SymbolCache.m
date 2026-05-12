classdef SymbolCache < handle
    %SymbolCache Wide symbol master joined from FTPCSD + FTPSEDOL [+ FTPCUSIP].
    %   Keyed by (srcId, ticker). Built from local FTP files, persisted as a
    %   parquet snapshot under cacheRoot/symbology so downstream lookups
    %   don't repeatedly re-parse the source CSVs.

    properties (SetAccess = immutable)
        Root (1,1) string
    end

    properties (Access = private)
        Tbl table
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

        function build(obj, opts)
            %BUILD Build the symbol master from local FTP files.
            %   Reads every FTPCSD file into a cell array of part-tables,
            %   harmonises categorical levels across parts, then performs
            %   a single bulk vertcat. Loop-vertcat reallocates on every
            %   iteration and exhausts memory on 311-source feeds; the
            %   one-shot vertcat plus categorical low-cardinality columns
            %   keeps the build inside the working set.
            arguments
                obj
                opts.FtpcsdFiles  (1,:) string = strings(0)
                opts.FtpsedolFile (1,1) string = ""
                opts.FtpcusipFile (1,1) string = ""
                opts.ShowProgress (1,1) logical = true
            end

            nFiles = numel(opts.FtpcsdFiles);
            parts = cell(nFiles, 1);

            if opts.ShowProgress && nFiles > 0
                bar = ice.util.Progress(nFiles, "FTPCSD read");
            else
                bar = ice.util.Progress.empty;
            end

            for k = 1:nFiles
                parts{k} = ice.ftp.readFtpcsd(opts.FtpcsdFiles(k));
                if ~isempty(bar); bar.tick(); end
            end
            if ~isempty(bar); bar.done(); end

            if nFiles == 0
                csd = table();
            else
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
                clear parts;  % free intermediate copies before the join
            end

            if strlength(opts.FtpsedolFile) > 0
                if opts.ShowProgress
                    fprintf("[merge]     joining FTPSEDOL...\n");
                end
                sed = ice.ftp.readFtpsedol(opts.FtpsedolFile);
                csd = obj.mergeOnSrcTicker(csd, sed, "sedolFromSedolFile");
            end

            obj.Tbl = csd;
            obj.persistSnapshot();
        end

        function tbl = table(obj)
            tbl = obj.Tbl;
        end

        function row = lookup(obj, srcId, ticker)
            arguments
                obj
                srcId (1,1) uint32
                ticker (1,1) string
            end
            if isempty(obj.Tbl)
                obj.loadSnapshotIfAvailable();
            end
            mask = obj.Tbl.srcId == srcId & obj.Tbl.ticker == ticker;
            row = obj.Tbl(mask, :);
        end

        function loadSnapshot(obj)
            obj.loadSnapshotIfAvailable();
        end
    end

    methods (Access = private)
        function out = mergeOnSrcTicker(~, left, right, sedolColName)
            % Force string keys on both sides so outerjoin lines up.
            left.ticker  = string(left.ticker);
            right.ticker = string(right.ticker);

            % Re-label the SEDOL coming from FTPSEDOL so we can compare/prefer
            % it against any SEDOL already present in FTPCSD.
            right.Properties.VariableNames{strcmp(right.Properties.VariableNames, "sedol")} = char(sedolColName);

            out = outerjoin(left, right, ...
                Keys=["srcId", "ticker"], MergeKeys=true);

            % Prefer FTPSEDOL's SEDOL when FTPCSD's is empty / missing.
            if ismember("sedol", string(out.Properties.VariableNames)) && ...
               ismember(sedolColName, string(out.Properties.VariableNames))
                cur = out.sedol;
                cur(strlength(cur) == 0 | ismissing(cur)) = ...
                    out.(sedolColName)(strlength(cur) == 0 | ismissing(cur));
                out.sedol = cur;
                out.(sedolColName) = [];
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
    end
end

function parts = harmonizePartSchemas(parts)
% Align parts so vertcat doesn't fail on (a) missing columns, (b) mismatched
% column orders, or (c) mismatched categorical levels.

% (a) collect the union of column names + their target types.
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

% (b) for each part, add missing cols (with the right type) and reorder.
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

% (c) categorical level alignment. For every column that is categorical
% in *any* part, compute the union of categories across all parts and
% reassign in each part so vertcat sees identical level sets.
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
