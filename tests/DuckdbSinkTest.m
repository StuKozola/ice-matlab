classdef DuckdbSinkTest < matlab.unittest.TestCase
    %DuckdbSinkTest Exercises ice.io.toDuckdb.
    %   ice.io.toDuckdb requires R2026a+ for duckdb(). On older releases
    %   the function errors with a typed exception; that's the only path
    %   we can exercise on this machine. Tests that need a live
    %   connection are skipped on older MATLAB via assumeTrue.

    properties (Access = private)
        HasDuckdb logical
    end

    methods (TestClassSetup)
        function detectDuckdb(tc)
            tc.HasDuckdb = exist("duckdb", "file") == 2;
        end
    end

    methods (Test)
        function unsupportedReleaseRaisesTypedException(tc)
            tc.assumeFalse(tc.HasDuckdb, ...
                "Test only meaningful on releases without duckdb()");
            tc.verifyError(@() ice.io.toDuckdb(), ...
                "ice:io:toDuckdb:Unsupported");
        end

        function liveOpenAndQueryReturnsView(tc)
            tc.assumeTrue(tc.HasDuckdb, "Requires R2026a+ duckdb()");

            % Build a tiny parquet under a temp cache root, point
            % toDuckdb at it, and verify the view round-trips.
            tmpRoot = string(tempname()); mkdir(tmpRoot);
            cleanup = onCleanup(@() rmIfExists(tmpRoot)); %#ok<NASGU>

            partDir = fullfile(tmpRoot, "symbology", "parts");
            mkdir(partDir);
            part = table(uint32([558;558]), ["AAPL";"MSFT"], ["2046251";"2588173"], ...
                VariableNames=["srcId","ticker","sedol"]);
            parquetwrite(fullfile(partDir, "part_00558.parquet"), part);

            conn = ice.io.toDuckdb(CacheRoot=tmpRoot);
            connCleanup = onCleanup(@() close(conn)); %#ok<NASGU>

            t = fetch(conn, "SELECT ticker, sedol FROM symbology_master ORDER BY ticker");
            tc.verifyEqual(height(t), 2);
            tc.verifyEqual(string(t.ticker(1)), "AAPL");
            tc.verifyEqual(string(t.sedol(1)), "2046251");
        end
    end
end

function rmIfExists(p)
if isfolder(p)
    try; rmdir(p, "s"); catch; end %#ok<NOSEMI>
end
end
