classdef FileLock < handle
    %FileLock SMB-safe exclusive lock backed by a sentinel file.
    %   lock = ice.util.FileLock(path) acquires an exclusive lock at path.
    %   Reclaims stale locks older than StaleAfter seconds (default 4 h).
    %   Released automatically when the object goes out of scope.

    properties (SetAccess = immutable)
        Path (1,1) string
        StaleAfter (1,1) duration = hours(4)
    end

    properties (Access = private)
        Fid (1,1) double = -1
    end

    methods
        function obj = FileLock(path, opts)
            arguments
                path (1,1) string
                opts.StaleAfter (1,1) duration = hours(4)
                opts.WaitTimeout (1,1) duration = seconds(0)  % 0 = fail fast
                opts.PollInterval (1,1) duration = seconds(0.5)
            end
            obj.Path = path;
            obj.StaleAfter = opts.StaleAfter;

            parent = fileparts(path);
            if strlength(parent) > 0 && ~isfolder(parent)
                mkdir(parent);
            end

            deadline = datetime("now") + opts.WaitTimeout;
            while true
                if isfile(path)
                    info = dir(path);
                    age = datetime("now") - datetime(info.datenum, ConvertFrom="datenum");
                    if age > obj.StaleAfter
                        try; delete(path); catch; end %#ok<NOSEMI>
                    end
                end
                if obj.tryClaim(path)
                    return
                end
                if datetime("now") >= deadline
                    error("ice:util:FileLock:Busy", ...
                        "Could not acquire lock %s within %s", path, string(opts.WaitTimeout));
                end
                pause(seconds(opts.PollInterval));
            end
        end

        function tf = tryClaim(obj, path)
            % Atomically claim the lock by moving a uniquely-named temp file
            % onto the target path. movefile fails if the destination already
            % exists, which gives us the atomicity we need cross-platform.
            tf = false;
            tmp = path + ".tmp." + string(feature("getpid")) + "." + ...
                string(tic());
            fid = fopen(tmp, "w");
            if fid == -1
                return
            end
            fprintf(fid, "pid=%d host=%s acquired=%s\n", ...
                feature("getpid"), string(getenv("COMPUTERNAME")), ...
                datetime("now", Format="yyyy-MM-dd'T'HH:mm:ss"));
            fclose(fid);
            if isfile(path)
                try; delete(tmp); catch; end %#ok<NOSEMI>
                return
            end
            [ok, ~] = movefile(tmp, path);
            if ok
                obj.Fid = 1;  % sentinel: "we own the lock"
                tf = true;
            else
                try; delete(tmp); catch; end %#ok<NOSEMI>
            end
        end

        function delete(obj)
            if obj.Fid ~= -1 && isfile(obj.Path)
                try; delete(obj.Path); catch; end %#ok<NOSEMI>
            end
            obj.Fid = -1;
        end
    end
end
