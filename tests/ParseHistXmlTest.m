classdef ParseHistXmlTest < matlab.unittest.TestCase

    properties
        FixDaily string
        FixIntraday string
        FixLiveDaily string
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.FixDaily      = string(fullfile(here, "fixtures", "api", "xhist_ice_5d.xml"));
            tc.FixIntraday   = string(fullfile(here, "fixtures", "api", "xtick_ice_intraday.xml"));
            tc.FixLiveDaily  = string(fullfile(here, "fixtures", "api", "xhist_live_ibm.xml"));
            tc.assumeTrue(isfile(tc.FixDaily));
            tc.assumeTrue(isfile(tc.FixIntraday));
            tc.assumeTrue(isfile(tc.FixLiveDaily));
        end
    end

    methods (Test)
        function dailyShape(tc)
            xml = string(fileread(tc.FixDaily));
            tt = ice.api.parseHist(xml);
            tc.verifyEqual(height(tt), 4);
            tc.verifyEqual(string(tt.Properties.VariableNames), ...
                ["open","high","low","close","volume","openinterest"]);
            tc.verifyEqual(tt.open(1), 100960000);
            tc.verifyEqual(tt.volume(1), 3587660);
            tc.verifyEqual(tt.Properties.RowTimes(1), ...
                datetime(2020,8,10, TimeZone="UTC"));
        end

        function dailySymbolStored(tc)
            xml = string(fileread(tc.FixDaily));
            tt = ice.api.parseHist(xml);
            tc.verifyEqual(string(tt.Properties.CustomProperties.symbol), "ICE");
        end

        function intradayShapeAndTime(tc)
            xml = string(fileread(tc.FixIntraday));
            tt = ice.api.parseHist(xml);
            tc.verifyEqual(height(tt), 3);
            tc.verifyEqual(tt.open(1), 114280000);
            tc.verifyEqual(tt.Properties.RowTimes(1), ...
                datetime(2021,5,24,11,2,0, TimeZone="UTC"));
            tc.verifyEqual(tt.Properties.RowTimes(end), ...
                datetime(2021,5,24,11,6,0, TimeZone="UTC"));
        end

        function intradayHasNoOpenInterest(tc)
            xml = string(fileread(tc.FixIntraday));
            tt = ice.api.parseHist(xml);
            tc.verifyTrue(all(isnan(tt.openinterest)));
        end

        function xcptIsRaised(tc)
            xml = '<?xml version="1.0"?><xcpt n="not-entitled"/>';
            tc.verifyError(@() ice.api.parseHist(xml), "ice:api:ResponseError");
        end

        function liveDailyFormatParsed(tc)
            % Live xhist response uses <bar date="yyyy-MM-dd"> with decimal
            % prices, different from the user-guide sample which uses
            % <r date="yyyy/MM/dd"> with integer-scaled prices.
            xml = string(fileread(tc.FixLiveDaily));
            tt = ice.api.parseHist(xml);
            tc.verifyEqual(height(tt), 5);
            tc.verifyEqual(tt.open(1), 229.73);
            tc.verifyEqual(tt.high(1), 230.705);
            tc.verifyEqual(tt.volume(1), 5332800);
            tc.verifyEqual(tt.Properties.RowTimes(1), ...
                datetime(2026,5,8, TimeZone="UTC"));
            tc.verifyEqual(string(tt.Properties.CustomProperties.symbol), "IBM");
        end
    end
end
