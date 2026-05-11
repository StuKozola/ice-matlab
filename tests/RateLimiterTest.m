classdef RateLimiterTest < matlab.unittest.TestCase

    methods (Test)
        function concurrencyCapEnforced(tc)
            limiter = ice.util.RateLimiter( ...
                MaxConcurrent=3, MaxPerSecond=1000, ...
                Clock=@() 0, Sleeper=@(s) []);
            for k = 1:3
                limiter.acquire();
            end
            tc.verifyEqual(limiter.inFlight(), 3);
        end

        function releaseFreesSlot(tc)
            limiter = ice.util.RateLimiter( ...
                MaxConcurrent=2, MaxPerSecond=1000, ...
                Clock=@() 0, Sleeper=@(s) []);
            limiter.acquire();
            limiter.acquire();
            tc.verifyEqual(limiter.inFlight(), 2);
            limiter.release();
            tc.verifyEqual(limiter.inFlight(), 1);
        end

        function rateCapEnforcedWithFakeClock(tc)
            addpath(fullfile(fileparts(mfilename("fullpath")), "helpers"));
            clk = MutableClock();
            limiter = ice.util.RateLimiter( ...
                MaxConcurrent=100, MaxPerSecond=5, ...
                Clock=@() clk.read(), Sleeper=@(s) []);

            for k = 1:5
                limiter.acquire();
                limiter.release();
            end
            tc.verifyEqual(limiter.recentCount(), 5);

            clk.Now = 1.01;
            tc.verifyEqual(limiter.recentCount(), 0);
        end

        function slotGuardAutoReleases(tc)
            limiter = ice.util.RateLimiter( ...
                MaxConcurrent=2, MaxPerSecond=1000, ...
                Clock=@() 0, Sleeper=@(s) []);
            inner = @() innerAcquire(limiter);
            inner();
            tc.verifyEqual(limiter.inFlight(), 0);
        end
    end
end

function innerAcquire(limiter)
guard = limiter.acquireSlot(); %#ok<NASGU>
% guard goes out of scope -> release() fires
end
