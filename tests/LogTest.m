classdef LogTest < matlab.unittest.TestCase

    properties
        TempRoot string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname());
            mkdir(tc.TempRoot);
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function writesJsonLine(tc)
            ice.util.log("test_event", struct("a", 1, "b", "x"), ...
                Root=tc.TempRoot, Echo=false);
            today = string(datetime("now", Format="yyyy-MM-dd"));
            file = fullfile(tc.TempRoot, "logs", today + ".log");
            tc.verifyTrue(isfile(file));
            line = strip(string(fileread(file)));
            rec = jsondecode(line);
            tc.verifyEqual(string(rec.event), "test_event");
            tc.verifyEqual(string(rec.level), "info");
            tc.verifyEqual(rec.payload.a, 1);
            tc.verifyEqual(string(rec.payload.b), "x");
        end
    end
end
