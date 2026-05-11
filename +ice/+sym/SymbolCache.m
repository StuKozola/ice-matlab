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
            arguments
                obj
                opts.FtpcsdFiles  (1,:) string = strings(0)
                opts.FtpsedolFile (1,1) string = ""
                opts.FtpcusipFile (1,1) string = ""
            end

            csd = table();
            for f = opts.FtpcsdFiles
                part = ice.ftp.readFtpcsd(f);
                csd = vertcat(csd, part); %#ok<AGROW>
            end

            if strlength(opts.FtpsedolFile) > 0
                sed = ice.ftp.readFtpsedol(opts.FtpsedolFile);
                % Outer-join so we keep symbols present in only one source.
                csd = obj.mergeOnSrcTicker(csd, sed, "sedolFromSedolFile");
            end

            % CUSIP wiring deferred until a fixture / live file is available.

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
