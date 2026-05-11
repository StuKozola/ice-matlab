%[text] # ICE FTP Smoke Test
%[text] Run this script once to verify your credentials and that the FTP layer can reach the ICE EOD servers.
%[text] Prerequisites:
%[text] - Either run `ice.config.setupVault()` once and enter your `ICE_FTP_USER` / `ICE_FTP_PWD` at the prompt, **or** place them in a `.env` file at the toolbox root. See `.env.example` for the format.
%[text] What this script does:
%[text] - Opens an FTP session against `eod11/eod12/eod13.icedataservices.com` (whichever responds first). ICE production hosts speak plain FTP on port 21 only; SFTP is reserved for `idsftp.icedataservices.com` (developer test site).
%[text] - Defaults to `TlsMode="opportunistic"` so the connection upgrades to FTPS via `AUTH TLS` if the server supports it, and stays cleartext otherwise. Pass `TlsMode="strict"` to require TLS.
%[text] - Lists the root directory, looks for FTPSEDOL and FTPCSD entries, and reports the active host.
%[text] - Closes the session cleanly. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the session
%[text] To connect to the developer SFTP host instead, pass `Protocol="sftp"`.
session = ice.ftp.FtpSession();
fprintf("Connected to: %s as %s\n", session.activeHost(), ...
    ice.config.credentials("ICE_FTP_USER"));
%%
%[text] ## Top-level listing
top = session.list(".");
disp(top(1:min(20, numel(top))))
fprintf("Total entries in root: %d\n", numel(top));
%%
%[text] ## Look for FTPSEDOL
if any(top == "FTPSEDOL")
    sedolDir = session.list("FTPSEDOL");
    fprintf("FTPSEDOL/ has %d entries; first few:\n", numel(sedolDir));
    disp(sedolDir(1:min(10, numel(sedolDir))))
else
    fprintf("FTPSEDOL not present in root listing.\n");
end
%%
%[text] ## Look for FTPCSD
csdNames = ice.ftp.listing(session, "FTPCSD");
fprintf("FTPCSD files visible at root: %d\n", numel(csdNames));
if numel(csdNames) > 0
    disp(csdNames(1:min(5, numel(csdNames))))
end
%%
%[text] ## Close
session.close();
fprintf("Session closed.\n");
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
