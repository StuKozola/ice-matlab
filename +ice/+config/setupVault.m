function setupVault(opts)
%SETUPVAULT One-time helper: prompt for ICE credentials and store in MATLAB Vault.
%   ice.config.setupVault()              prompts for all four keys
%   ice.config.setupVault(Keys=["..."])  prompts only for the listed keys
%   ice.config.setupVault(Overwrite=true) replaces existing Vault entries
%
%   MATLAB's setSecret prompts for the value itself (the API does not accept
%   the value as a function argument — this is by design so the secret never
%   appears in command history or workspace). This wrapper just iterates the
%   keys and calls setSecret for each, skipping any that already exist unless
%   Overwrite is set.

arguments
    opts.Keys (1,:) string = ["ICE_FTP_USER", "ICE_FTP_PWD", "ICE_API_USER", "ICE_API_PWD"]
    opts.Overwrite (1,1) logical = false
end

for k = opts.Keys
    if isSecret(k) && ~opts.Overwrite
        fprintf("[skip] %s already in Vault (pass Overwrite=true to replace)\n", k);
        continue
    end
    setSecret(char(k), Overwrite=opts.Overwrite);
    fprintf("[ok]   %s saved to Vault\n", k);
end
end
