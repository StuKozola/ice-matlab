classdef FtpcsdReaderTest < matlab.unittest.TestCase

    properties
        Fixture string
    end

    methods (TestClassSetup)
        function findFixture(tc)
            here = fileparts(mfilename("fullpath"));
            tc.Fixture = string(fullfile(here, "fixtures", "ftp", "FTPCSD_sample.csv"));
            tc.assumeTrue(isfile(tc.Fixture), "Fixture missing: " + tc.Fixture);
        end
    end

    methods (Test)
        function renamedColumnsPresent(tc)
            t = ice.ftp.readFtpcsd(tc.Fixture);
            vars = string(t.Properties.VariableNames);
            for expected = ["srcId","ticker","sedol","isin","name","mic", ...
                            "strikePrice","expirationDate","currency", ...
                            "tickSize","contractSize"]
                tc.verifyTrue(any(vars == expected), ...
                    "Missing column: " + expected);
            end
        end

        function typeCoercions(tc)
            t = ice.ftp.readFtpcsd(tc.Fixture);
            tc.verifyClass(t.srcId, "uint32");
            tc.verifyClass(t.strikePrice, "double");
            tc.verifyClass(t.expirationDate, "datetime");
            tc.verifyClass(t.tickSize, "double");
        end

        function strikeAndExpirationParsedForFuture(tc)
            t = ice.ftp.readFtpcsd(tc.Fixture);
            future = t(t.ticker == "ES'2025'H", :);
            tc.verifyEqual(height(future), 1);
            tc.verifyEqual(future.strikePrice, 6000);
            tc.verifyEqual(future.expirationDate, datetime(2025,3,21));
            tc.verifyEqual(future.contractSize, 50);
        end

        function originalTokensPreservedInDescription(tc)
            t = ice.ftp.readFtpcsd(tc.Fixture);
            descs = string(t.Properties.VariableDescriptions);
            % srcId came from <ENUM.SRC.ID>
            srcIdIdx = find(string(t.Properties.VariableNames) == "srcId", 1);
            tc.verifyEqual(descs(srcIdIdx), "<ENUM.SRC.ID>");
        end
    end
end
