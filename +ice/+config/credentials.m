function value = credentials(name, opts)
%CREDENTIALS Resolve a named credential via Vault -> .env -> process env.
%   value = ice.config.credentials("ICE_FTP_USER")
%
%   Resolution order:
%     1. MATLAB Vault (getSecret)        — primary, secure
%     2. .env file at toolbox root       — backup, gitignored
%     3. Process environment variable    — for Task Scheduler use
%
%   Throws ice:config:credentials:NotFound if no source has the value (unless
%   Default is supplied).

arguments
    name (1,1) string
    opts.Default (1,1) string = string(missing)
    opts.EnvFile (1,1) string = ""
end

try
    if isSecret(name)
        value = string(getSecret(name));
        return
    end
catch err
    if ~contains(err.identifier, "Undefined") && ~contains(err.identifier, "License")
        rethrow(err);
    end
end

envFile = opts.EnvFile;
if strlength(envFile) == 0
    envFile = fullfile(toolboxRoot(), ".env");
end
if isfile(envFile)
    kv = parseEnvFile(envFile);
    if isfield(kv, char(name))
        value = string(kv.(char(name)));
        return
    end
end

raw = getenv(name);
if strlength(string(raw)) > 0
    value = string(raw);
    return
end

if ~ismissing(opts.Default)
    value = opts.Default;
    return
end

error("ice:config:credentials:NotFound", ...
    "Credential '%s' not found in Vault, %s, or environment.", name, envFile);
end

function r = toolboxRoot()
here = fileparts(mfilename("fullpath"));
r = fileparts(fileparts(here));
end

function kv = parseEnvFile(file)
kv = struct();
fid = fopen(file, "r", "n", "UTF-8");
if fid == -1
    return
end
cleanup = onCleanup(@() fclose(fid));
while ~feof(fid)
    line = string(fgetl(fid));
    if ismissing(line) || strlength(strip(line)) == 0
        continue
    end
    line = strip(line);
    if startsWith(line, "#")
        continue
    end
    eqIdx = strfind(line, "=");
    if isempty(eqIdx)
        continue
    end
    key = strip(extractBefore(line, eqIdx(1)));
    val = strip(extractAfter(line, eqIdx(1)));
    if startsWith(val, '"') && endsWith(val, '"')
        val = extractBetween(val, 2, strlength(val) - 1);
    end
    if isvarname(key)
        kv.(char(key)) = val;
    end
end
end
