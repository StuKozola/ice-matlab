function v = getSecret(name)
%getSecret Stub for tests: reads ICE_FAKE_VAULT env var.
raw = string(getenv("ICE_FAKE_VAULT"));
if strlength(raw) == 0
    error("MATLAB:secret:NotFound", "no fake vault set");
end
m = jsondecode(char(raw));
if ~isfield(m, char(name))
    error("MATLAB:secret:NotFound", "secret %s not in fake vault", name);
end
v = string(m.(char(name)));
end
