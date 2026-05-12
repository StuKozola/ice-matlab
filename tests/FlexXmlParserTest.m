classdef FlexXmlParserTest < matlab.unittest.TestCase
    %FlexXmlParserTest Exercises parseFlexXml against captured fixtures.
    %   The doc-example happy path verifies dynamic header schema handling
    %   and compound RT_BarData fields. The Not-Entitled fixture verifies
    %   the error envelope surfaces as a typed exception rather than an
    %   empty table.

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
        function exampleGFSHasDynamicSchema(tc)
            xml = string(fileread(fullfile(tc.FixDir, "flexhistory_example_GFS.xml")));
            tbl = ice.api.parseFlex(xml);

            tc.verifyEqual(height(tbl), 5);
            vars = string(tbl.Properties.VariableNames);

            % Simple scalar fields land as columns.
            tc.verifyTrue(any(vars == "interval_start"));
            tc.verifyTrue(any(vars == "flags"));
            tc.verifyTrue(any(vars == "bar_length"));

            % Compound RT_BarData field expands to <field>_<element> columns.
            tc.verifyTrue(any(vars == "tmp_2m_open"));
            tc.verifyTrue(any(vars == "tmp_2m_high"));
            tc.verifyTrue(any(vars == "tmp_2m_low"));
            tc.verifyTrue(any(vars == "tmp_2m_average"));

            % time-typed fields are datetimes in UTC.
            tc.verifyClass(tbl.interval_start, "datetime");
            tc.verifyEqual(string(tbl.interval_start.TimeZone), "UTC");
            tc.verifyEqual(tbl.interval_start(1), ...
                datetime(1697868000, ConvertFrom="posixtime", TimeZone="UTC"));

            % Values from row 1 of the fixture.
            tc.verifyEqual(tbl.tmp_2m_open(1), 12.57);
            tc.verifyEqual(tbl.tmp_2m_average(1), 12.57);

            % Symbol column is populated from <data id="...">.
            tc.verifyEqual(string(tbl.symbol(1)), "EDDH MR0!-GFS");
        end

        function notEntitledRaisesTypedException(tc)
            xml = string(fileread(fullfile(tc.FixDir, "flexhistory_not_entitled.xml")));
            tc.verifyError(@() ice.api.parseFlex(xml), "ice:api:NotEntitled");
        end
    end
end
