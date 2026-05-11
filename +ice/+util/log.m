function log(event, payload, opts)
%LOG Append a structured JSON-line event to the daily log file.
arguments
    event (1,1) string
    payload struct = struct()
    opts.Level (1,1) string {mustBeMember(opts.Level, ["debug","info","warn","error"])} = "info"
    opts.Root (1,1) string = ""
    opts.Echo (1,1) logical = true
end
if strlength(opts.Root) == 0
    root = ice.config.cacheRoot();
else
    root = opts.Root;
end
logDir = fullfile(root, "logs");
if ~isfolder(logDir)
    mkdir(logDir);
end
today = string(datetime("now", Format="yyyy-MM-dd"));
file = fullfile(logDir, today + ".log");

record = struct( ...
    "ts", string(datetime("now", TimeZone="UTC", Format="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")), ...
    "level", opts.Level, ...
    "event", event, ...
    "payload", payload);
line = jsonencode(record);

fid = fopen(file, "a", "n", "UTF-8");
if fid ~= -1
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, "%s\n", line);
end

if opts.Echo
    fprintf("[%s] %s %s\n", upper(opts.Level), event, summarize(payload));
end
end

function s = summarize(p)
fn = fieldnames(p);
if isempty(fn)
    s = "";
    return
end
parts = strings(numel(fn), 1);
for k = 1:numel(fn)
    v = p.(fn{k});
    if isnumeric(v) && isscalar(v)
        parts(k) = sprintf("%s=%g", fn{k}, v);
    elseif (ischar(v) || isstring(v)) && isscalar(string(v))
        parts(k) = sprintf("%s=%s", fn{k}, string(v));
    else
        parts(k) = sprintf("%s=<%s>", fn{k}, class(v));
    end
end
s = strjoin(parts, " ");
end
