classdef RetryTest < matlab.unittest.TestCase

    methods (Test)
        function succeedsFirstTry(tc)
            calls = 0;
            fn = @() bumpAndReturn();
            out = ice.util.Retry(fn, Sleeper=@(s) []);
            tc.verifyEqual(out, 1);

            function v = bumpAndReturn()
                calls = calls + 1;
                v = calls;
            end
        end

        function retriesOnTransientThenSucceeds(tc)
            calls = 0;
            fn = @() flakyCall();
            out = ice.util.Retry(fn, ...
                MaxAttempts=4, InitialDelay=0.001, Sleeper=@(s) [], ...
                IsTransient=@(e) true);
            tc.verifyEqual(out, "ok");
            tc.verifyEqual(calls, 3);

            function v = flakyCall()
                calls = calls + 1;
                if calls < 3
                    error("ice:test:Transient", "fail %d", calls);
                end
                v = "ok";
            end
        end

        function reThrowsOnNonTransient(tc)
            fn = @() error("ice:test:Permanent", "nope");
            tc.verifyError(@() ice.util.Retry(fn, ...
                Sleeper=@(s) [], IsTransient=@(e) false), ...
                "ice:test:Permanent");
        end

        function reThrowsAfterMaxAttempts(tc)
            fn = @() error("ice:test:Transient", "always fails");
            tc.verifyError(@() ice.util.Retry(fn, ...
                MaxAttempts=3, InitialDelay=0.001, Sleeper=@(s) [], ...
                IsTransient=@(e) true), ...
                "ice:test:Transient");
        end
    end
end
