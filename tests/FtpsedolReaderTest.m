classdef FtpsedolReaderTest < matlab.unittest.TestCase

    properties
        Fixture string
    end

    methods (TestClassSetup)
        function findFixture(tc)
            here = fileparts(mfilename("fullpath"));
            tc.Fixture = string(fullfile(here, "fixtures", "ftp", "FTPSEDOL_sample.csv"));
            tc.assumeTrue(isfile(tc.Fixture), "Fixture missing: " + tc.Fixture);
        end
    end

    methods (Test)
        function shapeAndColumns(tc)
            t = ice.ftp.readFtpsedol(tc.Fixture);
            tc.verifyEqual(string(t.Properties.VariableNames), ...
                ["srcId", "ticker", "sedol"]);
            tc.verifyEqual(height(t), 9);
            tc.verifyClass(t.srcId, "uint32");
            tc.verifyClass(t.ticker, "string");
            tc.verifyClass(t.sedol, "string");
        end

        function valuesPreserved(tc)
            t = ice.ftp.readFtpsedol(tc.Fixture);
            tc.verifyEqual(t.srcId(1), uint32(193));
            tc.verifyEqual(t.ticker(1), "E:ACSEL.E");
            tc.verifyEqual(t.sedol(1), "B85QH63");
            tc.verifyEqual(t.srcId(end), uint32(1795));
            tc.verifyEqual(t.ticker(end), "E:ZOTE");
            tc.verifyEqual(t.sedol(end), "5770900");
        end

        function readsCompressedGz(tc)
            tdir = string(tempname()); mkdir(tdir);
            cleanup = onCleanup(@() rmdir(tdir, "s")); %#ok<NASGU>
            copy = fullfile(tdir, "FTPSEDOL_PUB1_20260101.csv");
            copyfile(tc.Fixture, copy);
            gzip(char(copy));
            delete(copy);
            t = ice.ftp.readFtpsedol(copy + ".gz");
            tc.verifyEqual(height(t), 9);
            tc.verifyEqual(t.sedol(1), "B85QH63");
        end
    end
end
