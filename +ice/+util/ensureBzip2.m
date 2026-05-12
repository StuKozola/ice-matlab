function exePath = ensureBzip2(opts)
%ENSUREBZIP2 Bootstrap a local copy of bzip2.exe (Windows) under cacheRoot/bin.
%   path = ice.util.ensureBzip2()
%   path = ice.util.ensureBzip2(Force=true)
%
%   If bzip2.exe is already on PATH, returns "bzip2" (PATH lookup wins).
%   Otherwise downloads bzip2-1.0.5-bin.zip from GnuWin32 on SourceForge,
%   verifies its SHA-256, extracts bzip2.exe + bzip2.dll into
%   <cacheRoot>/bin/, and returns the absolute path to bzip2.exe. Idempotent:
%   subsequent calls return the cached path without re-downloading.
%
%   ice.ftp.decompress consults this helper automatically when no bz2
%   backend is on PATH; on Linux/macOS systems where bzip2 is universally
%   installed this function is a no-op pass-through.

arguments
    opts.Force (1,1) logical = false
    opts.Url   (1,1) string  = "https://downloads.sourceforge.net/project/gnuwin32/bzip2/1.0.5/bzip2-1.0.5-bin.zip"
    opts.ExpectedSha256 (1,1) string = "97137e4b9ac9e116d0877f9d266927fea91ad117b011f80cf034fea4ef7a534e"
end

% If bzip2 is already on PATH, prefer that.
if ~opts.Force && hasExeOnPath("bzip2")
    exePath = "bzip2";
    return
end

if ~ispc
    % On Linux/macOS the system package manager installs bzip2, and our
    % decompress.m hasExe check will already find it. If somehow not,
    % surface a clear error rather than trying to download a Windows binary.
    if hasExeOnPath("bzip2")
        exePath = "bzip2";
        return
    end
    error("ice:util:ensureBzip2:NotWindows", ...
        "ensureBzip2 auto-bootstrap is Windows-only. Install bzip2 via your package manager.");
end

binDir = fullfile(ice.config.cacheRoot(), "bin");
if ~isfolder(binDir); mkdir(binDir); end
exePath = string(fullfile(binDir, "bzip2.exe"));
dllPath = string(fullfile(binDir, "bzip2.dll"));

if isfile(exePath) && isfile(dllPath) && ~opts.Force
    return
end

ice.util.log("bzip2_bootstrap_start", struct( ...
    "url", opts.Url, "binDir", string(binDir)));

zipPath = string(fullfile(tempdir, "bzip2-1.0.5-bin.zip"));
cleanupZip = onCleanup(@() safeDelete(zipPath));
websave(char(zipPath), char(opts.Url), ...
    weboptions(Timeout=120));

% Verify SHA-256.
actualSha = computeSha256(zipPath);
if strlength(opts.ExpectedSha256) > 0 && ~strcmpi(actualSha, opts.ExpectedSha256)
    error("ice:util:ensureBzip2:ChecksumMismatch", ...
        "Expected SHA-256 %s but got %s for %s", ...
        opts.ExpectedSha256, actualSha, opts.Url);
end

% Extract just the two files we need, into binDir flat (no bin/ subdir).
extractTo = string(tempname());
mkdir(extractTo);
cleanupExtract = onCleanup(@() rmdirSafe(extractTo));
unzip(char(zipPath), char(extractTo));

stagedExe = fullfile(extractTo, "bin", "bzip2.exe");
stagedDll = fullfile(extractTo, "bin", "bzip2.dll");
if ~isfile(stagedExe) || ~isfile(stagedDll)
    error("ice:util:ensureBzip2:UnexpectedZipLayout", ...
        "Downloaded zip did not contain bin/bzip2.exe or bin/bzip2.dll");
end
copyfile(stagedExe, char(exePath));
copyfile(stagedDll, char(dllPath));

ice.util.log("bzip2_bootstrap_done", struct( ...
    "exe", exePath, "bytes", dir(exePath).bytes));
end

% --------------------------------------------------------------------------

function tf = hasExeOnPath(name)
[status, ~] = system("where " + name + " 2>nul");
tf = status == 0;
end

function s = computeSha256(path)
% Use Windows' certutil (always present, no extra install, no .NET/Java).
[status, out] = system(sprintf('certutil -hashfile "%s" SHA256', path));
if status ~= 0
    error("ice:util:ensureBzip2:HashFailed", ...
        "certutil failed (%d): %s", status, out);
end
% Output looks like:
%   SHA256 hash of file.zip:
%   97137e4b9ac9e116d0877f9d266927fea91ad117b011f80cf034fea4ef7a534e
%   CertUtil: -hashfile command completed successfully.
lines = string(splitlines(out));
% Take the first line that's all hex and at least 64 chars.
hexLine = "";
for k = 1:numel(lines)
    candidate = strip(replace(lines(k), " ", ""));
    if strlength(candidate) >= 64 && ~isempty(regexp(candidate, "^[0-9a-fA-F]+$", "once"))
        hexLine = lower(extractBefore(candidate, 65));
        break;
    end
end
if strlength(hexLine) == 0
    error("ice:util:ensureBzip2:HashFailed", "Could not parse certutil output: %s", out);
end
s = hexLine;
end

function safeDelete(p)
if isfile(p); try; delete(p); catch; end; end %#ok<NOSEMI>
end

function rmdirSafe(p)
if isfolder(p); try; rmdir(p, "s"); catch; end; end %#ok<NOSEMI>
end
