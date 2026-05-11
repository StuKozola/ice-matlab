classdef DecompressTest < matlab.unittest.TestCase

    properties
        TempDir string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempDir = string(tempname());
            mkdir(tc.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if isfolder(tc.TempDir)
                rmdir(tc.TempDir, "s");
            end
        end
    end

    methods (Test)
        function gzipRoundTrip(tc)
            plain = fullfile(tc.TempDir, "data.csv");
            payload = "a,b,c" + newline + "1,2,3" + newline;
            writeFile(plain, payload);
            gzip(char(plain));
            delete(plain);
            tc.verifyTrue(isfile(plain + ".gz"));

            out = ice.ftp.decompress(plain + ".gz");
            tc.verifyEqual(string(out), plain);
            tc.verifyEqual(string(fileread(out)), payload);
        end

        function bz2RoundTripViaAvailableBackend(tc)
            % Skip if no bz2 backend is available on this machine.
            try
                py.bz2.compress(py.bytes(uint8(0)));
                havePy = true;
            catch
                havePy = false;
            end
            haveExe = systemHas("bzip2") || systemHas("7z");
            tc.assumeTrue(havePy || haveExe, ...
                "No bz2 backend on this machine (no python bz2, no bzip2.exe, no 7z.exe).");

            plain = fullfile(tc.TempDir, "data.csv");
            payload = "hdr1,hdr2" + newline + "x,y" + newline;
            writeFile(plain, payload);
            compressed = py.bz2.compress(py.bytes(uint8(char(payload))));
            bz2Path = fullfile(tc.TempDir, "data.csv.bz2");
            fid = fopen(bz2Path, "wb");
            fwrite(fid, uint8(compressed));
            fclose(fid);

            % Ensure plain doesn't exist so decompress has to actually write it.
            delete(plain);
            out = ice.ftp.decompress(bz2Path);
            tc.verifyEqual(string(out), string(plain));
            tc.verifyEqual(string(fileread(out)), payload);
        end

        function plainFilePassThrough(tc)
            plain = fullfile(tc.TempDir, "data.csv");
            writeFile(plain, "x");
            out = ice.ftp.decompress(plain);
            tc.verifyEqual(string(out), string(plain));
        end

        function cachedOutputReusedWhenPresent(tc)
            plain = fullfile(tc.TempDir, "data.csv");
            writeFile(plain, "original");
            gzip(char(plain));
            % Replace the on-disk plain to look like a stale cached copy.
            writeFile(plain, "cached");
            out = ice.ftp.decompress(plain + ".gz");
            % Without Force, the existing plain file should be returned untouched.
            tc.verifyEqual(string(fileread(out)), "cached");
        end
    end
end

function writeFile(p, s)
fid = fopen(p, "w");
fwrite(fid, uint8(char(s)));
fclose(fid);
end

function tf = systemHas(name)
[status, ~] = system("where " + name + " 2>nul");
tf = status == 0;
end
