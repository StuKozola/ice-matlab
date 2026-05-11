classdef CacheRootTest < matlab.unittest.TestCase

    properties
        TempRoot string
        OrigEnv string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname());
            tc.OrigEnv = string(getenv("ICE_CACHE_ROOT"));
            setenv("ICE_CACHE_ROOT", "");
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
        function overrideWins(tc)
            setenv("ICE_CACHE_ROOT", char(fullfile(tc.TempRoot, "fromenv")));
            r = ice.config.cacheRoot(fullfile(tc.TempRoot, "fromarg"));
            tc.verifyEqual(r, fullfile(tc.TempRoot, "fromarg"));
            tc.verifyTrue(isfolder(fullfile(r, "ftp_raw")));
            tc.verifyTrue(isfolder(fullfile(r, "parquet")));
            tc.verifyTrue(isfolder(fullfile(r, "logs")));
        end

        function envVarUsed(tc)
            envRoot = fullfile(tc.TempRoot, "viaEnv");
            setenv("ICE_CACHE_ROOT", char(envRoot));
            r = ice.config.cacheRoot();
            tc.verifyEqual(r, string(envRoot));
            tc.verifyTrue(isfolder(envRoot));
        end

        function defaultRootCreatesData(tc)
            setenv("ICE_CACHE_ROOT", "");
            r = ice.config.cacheRoot();
            tc.verifyTrue(isfolder(r));
            tc.verifyTrue(endsWith(r, "data"));
        end
    end
end
