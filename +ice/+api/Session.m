classdef Session < handle
    %Session HTTP client for ICE Connect Enterprise XML APIs.
    %   Wraps weboptions, a shared RateLimiter (default 8 in flight / 8 per
    %   second — half the ICE limit, leaves headroom for concurrent FTP
    %   work), exponential-back-off retry on transient errors, and gzip
    %   request encoding.
    %
    %   Used by ice.api.quote, ice.api.history, ice.api.intradayHistory,
    %   ice.api.flexHistory. Typically constructed once and reused.

    properties (SetAccess = immutable)
        Host (1,1) string
        Port (1,1) double = 443
        Username (1,1) string
        Limiter ice.util.RateLimiter
        Options
        UserAgent (1,1) string = "ice-matlab/0.1"
    end

    properties (Access = private)
        Password (1,1) string = ""
    end

    methods
        function obj = Session(opts)
            arguments
                opts.Host (1,1) string = "xml.dataservices.theice.com"
                opts.Port (1,1) double = 443
                opts.Username (1,1) string = ice.config.credentials("ICE_API_USER")
                opts.Password (1,1) string = ice.config.credentials("ICE_API_PWD")
                opts.MaxConcurrent (1,1) double = 8
                opts.MaxPerSecond (1,1) double = 8
                opts.RequestTimeout (1,1) duration = seconds(60)
            end
            obj.Host = opts.Host;
            obj.Port = opts.Port;
            obj.Username = opts.Username;
            obj.Password = opts.Password;
            obj.Limiter = ice.util.RateLimiter( ...
                MaxConcurrent=opts.MaxConcurrent, ...
                MaxPerSecond=opts.MaxPerSecond);
            obj.Options = weboptions( ...
                ContentType="text", ...
                CharacterEncoding="UTF-8", ...
                Timeout=seconds(opts.RequestTimeout), ...
                HeaderFields={'Accept-Encoding','gzip'}, ...
                UserAgent=char(obj.UserAgent));
        end

        function xml = request(obj, command, params)
            %REQUEST GET <host>/<command>?<params> with credentials.
            %   command : "quote", "options", "xhist", "xtick", "flexhistory"
            %   params  : struct of query parameters (excluding username/pwd)
            arguments
                obj
                command (1,1) string
                params struct = struct()
            end

            url = sprintf("https://%s:%d/%s", obj.Host, obj.Port, command);
            qp = obj.buildQuery(params);

            slot = obj.Limiter.acquireSlot(); %#ok<NASGU>
            started = tic;
            try
                xml = ice.util.Retry(@() webread(char(url + "?" + qp), obj.Options));
            catch err
                ice.util.log("api_request_failed", struct( ...
                    "command", command, ...
                    "id", err.identifier, ...
                    "message", err.message, ...
                    "elapsedSec", toc(started)), Level="warn");
                rethrow(err);
            end
            ice.util.log("api_request_ok", struct( ...
                "command", command, ...
                "bytes", strlength(string(xml)), ...
                "elapsedSec", toc(started)), Echo=false);
        end
    end

    methods (Access = private)
        function qp = buildQuery(obj, params)
            % Always add username/pwd; never log the resulting URL.
            params.username = obj.Username;
            params.pwd = obj.Password;
            keys = string(fieldnames(params));
            parts = strings(numel(keys), 1);
            for k = 1:numel(keys)
                key = keys(k);
                % ICE expects "options.<name>" but MATLAB struct fields
                % can't contain dots — endpoint code uses "options_<name>"
                % which we translate here.
                if startsWith(key, "options_")
                    queryKey = "options." + extractAfter(key, "options_");
                else
                    queryKey = key;
                end
                v = params.(key);
                parts(k) = queryKey + "=" + urlEncode(string(v));
            end
            qp = strjoin(parts, "&");
        end
    end
end

function out = urlEncode(in)
% Minimal URL-encoder that preserves comma and colon (used in ICE param values).
chars = char(in);
out = "";
for k = 1:numel(chars)
    c = chars(k);
    if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ...
            || (c >= '0' && c <= '9') ...
            || c == '-' || c == '_' || c == '.' || c == '~' ...
            || c == ',' || c == ':' || c == '!' || c == '|' || c == '%' ...
            || c == '/'
        out = out + string(c);
    elseif c == ' '
        out = out + "+";
    else
        out = out + sprintf("%%%02X", uint8(c));
    end
end
end
