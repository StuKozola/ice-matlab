function tf = isSecret(name)
%isSecret Stub for tests: reads ICE_FAKE_VAULT env var (JSON map of secrets).
v = decodeFake();
tf = isfield(v, char(name));
end

function s = decodeFake()
raw = string(getenv("ICE_FAKE_VAULT"));
if strlength(raw) == 0
    s = struct();
    return
end
try
    s = jsondecode(char(raw));
catch
    s = struct();
end
end
