classdef CacheTest < matlab.unittest.TestCase

    properties
        TempRoot string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname());
            mkdir(tc.TempRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function rawAndParquetPaths(tc)
            c = ice.util.Cache(tc.TempRoot);
            tc.verifyTrue(endsWith(c.rawPath("FTPCSD_558.csv.gz"), ...
                fullfile("ftp_raw", "FTPCSD_558.csv.gz")));
            p = c.parquetPath("558", "2026-05-11");
            tc.verifyTrue(isfolder(p));
            tc.verifyTrue(contains(p, "srcid=558"));
            tc.verifyTrue(contains(p, "date=2026-05-11"));
        end

        function kvPutGetRoundTrip(tc)
            c = ice.util.Cache(tc.TempRoot);
            tbl = table((1:3).', ["a";"b";"c"], VariableNames=["n","s"]);
            c.put("symbology/snapshot", tbl);
            [v, hit] = c.get("symbology/snapshot");
            tc.verifyTrue(hit);
            tc.verifyEqual(v, tbl);
        end

        function kvMissReturnsEmpty(tc)
            c = ice.util.Cache(tc.TempRoot);
            [v, hit] = c.get("does-not-exist");
            tc.verifyFalse(hit);
            tc.verifyEmpty(v);
        end
    end
end
