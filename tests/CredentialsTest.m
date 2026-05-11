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

        function quotedValueStripsSurroundingQuotes(tc)
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, 'ICE_TEST_KEY="  pa$$ w=rd # not a comment  "\n');
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "  pa$$ w=rd # not a comment  ");
        end

        function valueMayContainEqualsSigns(tc)
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "ICE_TEST_KEY=a=b=c=d\n");
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "a=b=c=d");
        end

        function ignoresCommentsAndBlankLines(tc)
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "# top-of-file comment\n");
            fprintf(fid, "\n");
            fprintf(fid, "   \n");
            fprintf(fid, "# another comment\n");
            fprintf(fid, "ICE_TEST_KEY=real_value\n");
            fprintf(fid, "\n");
            fprintf(fid, "# trailing comment\n");
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "real_value");
        end

        function envFileBeatsProcessEnv(tc)
            setenv("ICE_TEST_KEY", "from_process");
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "ICE_TEST_KEY=from_env_file\n");
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "from_env_file");
        end

        function malformedKeysAreSkipped(tc)
            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "123BAD=should_be_ignored\n");
            fprintf(fid, "has space=also_ignored\n");
            fprintf(fid, "ICE_TEST_KEY=ok\n");
            fclose(fid);
            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "ok");
        end

        function vaultBeatsEnvFile(tc)
            % Shadow the real isSecret/getSecret with stubs that read a
            % JSON env var, so we can test precedence without touching the
            % real Vault (which has no programmatic setter).
            fakeDir = fullfile(fileparts(mfilename("fullpath")), ...
                "helpers", "fakeVault");
            addpath(fakeDir);
            origVault = string(getenv("ICE_FAKE_VAULT"));
            setenv("ICE_FAKE_VAULT", ...
                '{"ICE_TEST_KEY":"from_vault"}');
            cleanup = onCleanup(@() restoreEnv(fakeDir, origVault)); %#ok<NASGU>

            envFile = fullfile(tc.TempRoot, ".env");
            fid = fopen(envFile, "w");
            fprintf(fid, "ICE_TEST_KEY=from_env_file\n");
            fclose(fid);

            v = ice.config.credentials("ICE_TEST_KEY", EnvFile=envFile);
            tc.verifyEqual(v, "from_vault");
        end
    end
end

function restoreEnv(fakeDir, origVault)
rmpath(fakeDir);
setenv("ICE_FAKE_VAULT", char(origVault));
end
