classdef FileLockTest < matlab.unittest.TestCase

    properties
        TempRoot string
    end

    methods (TestMethodSetup)
        function makeTempRoot(tc)
            tc.TempRoot = string(tempname());
            mkdir(tc.TempRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanTempRoot(tc)
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function acquiresAndReleases(tc)
            lockPath = fullfile(tc.TempRoot, "first.lock");
            lock = ice.util.FileLock(lockPath); %#ok<NASGU>
            tc.verifyTrue(isfile(lockPath));
            clear lock;
            tc.verifyFalse(isfile(lockPath));
        end

        function secondAcquireFailsFast(tc)
            lockPath = fullfile(tc.TempRoot, "busy.lock");
            held = ice.util.FileLock(lockPath); %#ok<NASGU>
            tc.verifyError(@() ice.util.FileLock(lockPath), ...
                "ice:util:FileLock:Busy");
        end

        function staleLockIsReclaimed(tc)
            lockPath = fullfile(tc.TempRoot, "stale.lock");
            % Create a stale sentinel by hand.
            fid = fopen(lockPath, "w"); fclose(fid);
            % Push mtime well into the past.
            cmd = sprintf('powershell -NoProfile -Command "(Get-Item ''%s'').LastWriteTime = (Get-Date).AddHours(-10)"', ...
                lockPath);
            system(cmd);
            lock = ice.util.FileLock(lockPath, StaleAfter=hours(1)); %#ok<NASGU>
            tc.verifyTrue(isfile(lockPath));
        end
    end
end
