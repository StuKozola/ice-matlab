function varargout = Retry(fn, opts)
%RETRY Run fn with exponential back-off on transient errors.
arguments
    fn function_handle
    opts.MaxAttempts (1,1) double {mustBePositive,mustBeInteger} = 4
    opts.InitialDelay (1,1) double {mustBePositive} = 0.5
    opts.MaxDelay (1,1) double {mustBePositive} = 30
    opts.IsTransient function_handle = @ice.util.defaultIsTransient
    opts.Sleeper function_handle = @(s) pause(s)
    opts.Logger function_handle = function_handle.empty
end

delay = opts.InitialDelay;
lastErr = MException.empty;
for attempt = 1:opts.MaxAttempts
    try
        [varargout{1:nargout}] = fn();
        return
    catch err
        lastErr = err;
        if attempt == opts.MaxAttempts || ~opts.IsTransient(err)
            rethrow(err);
        end
        if ~isempty(opts.Logger)
            opts.Logger("retry", struct("attempt", attempt, ...
                "delay", delay, "id", err.identifier, "message", err.message));
        end
        opts.Sleeper(delay);
        delay = min(delay * 2, opts.MaxDelay);
    end
end
rethrow(lastErr);
end
