classdef RateLimiter < handle
    %RateLimiter Token bucket capping concurrent and per-second request rate.
    %   Enforces ICE Connect Enterprise API limits: ≤20 outstanding requests
    %   and ≤20 requests/second. Acquire a slot before issuing each HTTP call;
    %   release on completion (or use the slot guard returned by acquireSlot).

    properties (SetAccess = immutable)
        MaxConcurrent (1,1) double = 20
        MaxPerSecond  (1,1) double = 20
    end

    properties (Access = private)
        InFlight (1,1) double = 0
        Stamps   (1,:) double = []  % monotonic seconds for each issued request
        Clock    function_handle    % () -> seconds, replaceable in tests
        Sleeper  function_handle    % @(secs) sleep
    end

    methods
        function obj = RateLimiter(opts)
            arguments
                opts.MaxConcurrent (1,1) double {mustBePositive,mustBeInteger} = 20
                opts.MaxPerSecond  (1,1) double {mustBePositive,mustBeInteger} = 20
                opts.Clock         function_handle = @() seconds(datetime("now") - datetime(2000,1,1))
                opts.Sleeper       function_handle = @(s) pause(s)
            end
            obj.MaxConcurrent = opts.MaxConcurrent;
            obj.MaxPerSecond  = opts.MaxPerSecond;
            obj.Clock   = opts.Clock;
            obj.Sleeper = opts.Sleeper;
        end

        function acquire(obj)
            %ACQUIRE Block until a request slot is available, then claim it.
            while true
                now = obj.Clock();
                obj.Stamps = obj.Stamps(obj.Stamps > now - 1);
                if obj.InFlight < obj.MaxConcurrent && numel(obj.Stamps) < obj.MaxPerSecond
                    obj.InFlight = obj.InFlight + 1;
                    obj.Stamps(end+1) = now; %#ok<AGROW>
                    return
                end
                if numel(obj.Stamps) >= obj.MaxPerSecond
                    wait = 1 - (now - obj.Stamps(1));
                else
                    wait = 0.01;
                end
                obj.Sleeper(max(wait, 0.005));
            end
        end

        function release(obj)
            %RELEASE Mark an outstanding request as completed.
            obj.InFlight = max(0, obj.InFlight - 1);
        end

        function guard = acquireSlot(obj)
            %ACQUIRESLOT Acquire and return an onCleanup that releases on scope exit.
            obj.acquire();
            guard = onCleanup(@() obj.release());
        end

        function n = inFlight(obj)
            n = obj.InFlight;
        end

        function n = recentCount(obj)
            now = obj.Clock();
            obj.Stamps = obj.Stamps(obj.Stamps > now - 1);
            n = numel(obj.Stamps);
        end
    end
end
