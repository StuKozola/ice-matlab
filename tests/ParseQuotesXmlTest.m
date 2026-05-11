classdef ParseQuotesXmlTest < matlab.unittest.TestCase

    properties
        FixQuotes string
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.FixQuotes = string(fullfile(here, "fixtures", "api", "quote_equities_decimal.xml"));
            tc.assumeTrue(isfile(tc.FixQuotes));
        end
    end

    methods (Test)
        function shapeAndColumns(tc)
            xml = string(fileread(tc.FixQuotes));
            t = ice.api.parseQuotes(xml);
            tc.verifyEqual(height(t), 4);
            vars = string(t.Properties.VariableNames);
            for v = ["status","request","id","recent","high","low","open","last"]
                tc.verifyTrue(any(vars == v), "Missing column: " + v);
            end
        end

        function valuesAreNumeric(tc)
            xml = string(fileread(tc.FixQuotes));
            t = ice.api.parseQuotes(xml);
            tc.verifyEqual(t.recent(strcmp(string(t.id), "AAPL")), 122.18);
            tc.verifyEqual(t.high(strcmp(string(t.id), "GOOG")), 535.06);
        end

        function statusAndIdAreStrings(tc)
            xml = string(fileread(tc.FixQuotes));
            t = ice.api.parseQuotes(xml);
            tc.verifyEqual(string(t.status(1)), "ok");
            tc.verifyEqual(string(t.id(1)), "IBM");
        end

        function emptyQuotesYieldsEmptyTable(tc)
            xml = '<?xml version="1.0"?><quotes request="" retrieved=""></quotes>';
            t = ice.api.parseQuotes(xml);
            tc.verifyEqual(height(t), 0);
        end

        function xcptIsRaised(tc)
            xml = '<?xml version="1.0"?><xcpt n="bad-symbol"/>';
            tc.verifyError(@() ice.api.parseQuotes(xml), "ice:api:ResponseError");
        end
    end
end
