classdef SyncDailySymbologyTest < matlab.unittest.TestCase

    properties
        TempRoot string
        OrigEnv  string
        FixCsd   string
        FixSedol string
    end

    methods (TestClassSetup)
        function findFixtures(tc)
            here = fileparts(mfilename("fullpath"));
            tc.FixCsd   = string(fullfile(here, "fixtures", "ftp", "FTPCSD_sample.csv"));
            tc.FixSedol = string(fullfile(here, "fixtures", "ftp", "FTPSEDOL_sample.csv"));
            addpath(fullfile(here, "helpers"));
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
        function runsEndToEndWithCachedFiles(tc)
            % Pre-populate the cache with fixture files renamed to look like
            % real FTPCSD PUB1 files and a real FTPSEDOL PUB5 file. With the
            % cache hits all in place, no downloads will be attempted.
            csdLocal = fullfile(tc.TempRoot, "ftp_raw", ...
                "FTPCSD_PUB1_558_20260511.csv.bz2");
            sedolLocal = fullfile(tc.TempRoot, "ftp_raw", ...
                "FTPSEDOL_PUB5_20260511.csv.bz2");

            mkdir(fileparts(csdLocal));
            bzipCopy(tc.FixCsd, csdLocal);
            bzipCopy(tc.FixSedol, sedolLocal);

            listings = struct( ...
                "FTPCSD_PUB1", "FTPCSD_PUB1_558_20260511.csv.bz2", ...
                "FTPSEDOL_PUB5", "FTPSEDOL_PUB5_20260511.csv.bz2");
            fakeSession = FakeFtpSession(listings);

            summary = ice.jobs.syncDailySymbology( ...
                SessionFactory=@() fakeSession, SkipParallel=true);

            tc.verifyEqual(summary.csdSources, 1);
            tc.verifyEqual(summary.downloaded, 0);
            tc.verifyEqual(summary.alreadyCached, 2);
            tc.verifyGreaterThan(summary.masterRows, 0);
            tc.verifyTrue(isfile(fullfile(tc.TempRoot, ...
                "symbology", "symbol_master.parquet")));
            tc.verifyEmpty(fakeSession.DownloadCalls);
        end

        function errorsWhenNoSedolFile(tc)
            listings = struct( ...
                "FTPCSD_PUB1", "FTPCSD_PUB1_558_20260511.csv.bz2", ...
                "FTPSEDOL_PUB5", strings(0));
            fakeSession = FakeFtpSession(listings);

            tc.verifyError(@() ice.jobs.syncDailySymbology( ...
                SessionFactory=@() fakeSession, SkipParallel=true), ...
                "ice:jobs:syncDailySymbology:NoSedolFile");
        end
    end
end

function bzipCopy(plainSrc, bz2Dst)
% Encode a plain CSV file as bz2 for test fixtures.
data = fileread(plainSrc);
compressed = py.bz2.compress(py.bytes(uint8(data)));
fid = fopen(bz2Dst, "wb");
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint8(compressed));
end
