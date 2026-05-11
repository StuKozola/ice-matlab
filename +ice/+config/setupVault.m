function setupVault(opts)
%SETUPVAULT One-time helper: prompt for ICE credentials and store in MATLAB Vault.
%   ice.config.setupVault()              prompts for all four keys
%   ice.config.setupVault(Keys=["..."])  prompts only for the listed keys
%   ice.config.setupVault(Overwrite=true) replaces existing Vault entries

arguments
    opts.Keys (1,:) string = ["ICE_FTP_USER", "ICE_FTP_PWD", "ICE_API_USER", "ICE_API_PWD"]
    opts.Overwrite (1,1) logical = false
end

for k = opts.Keys
    if isSecret(k) && ~opts.Overwrite
        fprintf("[skip] %s already in Vault (pass Overwrite=true to replace)\n", k);
        continue
    end
    if endsWith(k, "_PWD") || endsWith(k, "_PASSWORD") || endsWith(k, "_TOKEN")
        v = string(getPasswordFromUser(sprintf("Enter value for %s: ", k)));
    else
        v = string(input(sprintf("Enter value for %s: ", k), "s"));
    end
    if strlength(v) == 0
        fprintf("[skip] empty value for %s\n", k);
        continue
    end
    setSecret(k, v);
    fprintf("[ok]   %s saved to Vault\n", k);
end
end

function pw = getPasswordFromUser(prompt)
fprintf("%s", prompt);
try
    rdr = java.io.BufferedReader(java.io.InputStreamReader(java.lang.System.in));
    pw = char(rdr.readLine());
catch
    pw = input("", "s");
end
end
