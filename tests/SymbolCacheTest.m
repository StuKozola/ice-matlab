classdef SymbolCacheTest < matlab.unittest.TestCase

    properties
        FixCsd string
        FixSedol string
        TempRoot string
        OrigEnv string
    end

    methods (TestClassSetup)
        function findFixtures(tc)
            here = fileparts(mfilename("fullpath"));
            tc.FixCsd = string(fullfile(here, "fixtures", "ftp", "FTPCSD_sample.csv"));
            tc.FixSedol = string(fullfile(here, "fixtures", "ftp", "FTPSEDOL_sample.csv"));
            tc.assumeTrue(isfile(tc.FixCsd));
            tc.assumeTrue(isfile(tc.FixSedol));
        end
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname()); mkdir(tc.TempRoot);
            tc.OrigEnv = string(getenv("ICE_CACHE_ROOT"));
            setenv("ICE_CACHE_ROOT", char(tc.TempRoot));
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            setenv("ICE_CACHE_ROOT", char(tc.OrigEnv));
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function buildFromCsdAlone(tc)
            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=tc.FixCsd);
            t = s.table();
            tc.verifyGreaterThan(height(t), 0);
            tc.verifyTrue(any(string(t.Properties.VariableNames) == "ticker"));
        end

        function lookupReturnsExactRow(tc)
            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=tc.FixCsd, FtpsedolFile=tc.FixSedol);
            row = s.lookup(uint32(558), "AAPL");
            tc.verifyEqual(height(row), 1);
            tc.verifyEqual(row.sedol, "2046251");
        end

        function sedolFromSedolFileFillsMissing(tc)
            % FTPCSD row for srcId 193 / "E:ACSEL.E" already has SEDOL B85QH63;
            % FTPSEDOL also has it. Ensure no collision and SEDOL preserved.
            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=tc.FixCsd, FtpsedolFile=tc.FixSedol);
            row = s.lookup(uint32(193), "E:ACSEL.E");
            tc.verifyEqual(height(row), 1);
            tc.verifyEqual(row.sedol, "B85QH63");
        end

        function snapshotPersistedToParquet(tc)
            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=tc.FixCsd);
            tc.verifyTrue(isfile(fullfile(tc.TempRoot, ...
                "symbology", "symbol_master.parquet")));
        end

        function loadSnapshotRehydrates(tc)
            s1 = ice.sym.SymbolCache();
            s1.build(FtpcsdFiles=tc.FixCsd);
            n = height(s1.table());

            s2 = ice.sym.SymbolCache();
            s2.loadSnapshot();
            tc.verifyEqual(height(s2.table()), n);
        end
    end
end
