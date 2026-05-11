classdef CredentialsTest < matlab.unittest.TestCase

    properties
        TempRoot string
        OrigEnv  string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname());
            mkdir(tc.TempRoot);
            tc.OrigEnv = string(getenv("ICE_TEST_KEY"));
            setenv("ICE_TEST_KEY", "");
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            setenv("ICE_TEST_KEY", char(tc.OrigEnv));
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function envFileLookupSucceeds(tc)
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "# a comment\n");
            fprintf(fid, "ICE_TEST_KEY=from_env_file\n");
            fprintf(fid, "OTHER=ignored\n");
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "from_env_file");
        end

        function processEnvFallback(tc)
            setenv("ICE_TEST_KEY", "from_process_env");
            v = ice.config.credentials("ICE_TEST_KEY", ...
                EnvFile=fullfile(tc.TempRoot, "missing.env"));
            tc.verifyEqual(v, "from_process_env");
        end

        function defaultUsedWhenAllSourcesEmpty(tc)
            v = ice.config.credentials("ICE_TEST_KEY", ...
                EnvFile=fullfile(tc.TempRoot, "missing.env"), ...
                Default="fallback");
            tc.verifyEqual(v, "fallback");
        end

        function throwsWhenNotFoundAndNoDefault(tc)
            tc.verifyError(@() ice.config.credentials("ICE_TEST_KEY", ...
                EnvFile=fullfile(tc.TempRoot, "missing.env")), ...
                "ice:config:credentials:NotFound");
        end
    end
end
