classdef OptionsXmlParserTest < matlab.unittest.TestCase
    %OptionsXmlParserTest Exercises parseOptionsXml against the live AAPL
    %   fixture (5 strikes of stock options captured from prod).

    properties
        FixDir string
    end

    methods (TestClassSetup)
        function findFixtures(tc)
            here = fileparts(mfilename("fullpath"));
            tc.FixDir = string(fullfile(here, "fixtures", "api"));
            tc.assumeTrue(isfolder(tc.FixDir));
        end
    end

    methods (Test)
        function aaplStockChainLongFormat(tc)
            xml = string(fileread(fullfile(tc.FixDir, "options_AAPL_stock.xml")));
            tbl = ice.api.parseOptions(xml);

            % Long format: one row per (strike, side). Fixture has 5 strikes.
            tc.verifyEqual(height(tbl), 10);

            % Both sides present.
            tc.verifyEqual(sort(unique(tbl.side)), ["call"; "put"]);

            % Chain-level metadata repeated on both rows of each strike.
            for k = 1:5
                pair = tbl((k-1)*2 + (1:2), :);
                tc.verifyEqual(pair.strike(1), pair.strike(2));
                tc.verifyEqual(pair.underlier(1), pair.underlier(2));
                tc.verifyEqual(pair.root(1), pair.root(2));
            end

            % Underlier from the XML body (the <underlier type="stock">AAPL</underlier> shape).
            tc.verifyTrue(any(tbl.underlier == "AAPL"));
            tc.verifyTrue(any(tbl.root == "O:AAPL"));

            % bid/ask are numeric.
            tc.verifyClass(tbl.bid, "double");
            tc.verifyClass(tbl.ask, "double");

            % delta and impvol per side make it through.
            vars = string(tbl.Properties.VariableNames);
            tc.verifyTrue(any(vars == "delta"));
            tc.verifyTrue(any(vars == "impvol"));
        end
    end
end
