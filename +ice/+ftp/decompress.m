function outPath = decompress(srcPath, opts)
%DECOMPRESS Decompress a .gz or .bz2 file (or pass through a plain file).
%   outPath = ice.ftp.private.decompress("FTPSEDOL.csv.bz2")
%
%   Decompression strategy by extension:
%     .gz    → MATLAB native gunzip
%     .bz2   → first available of: bzip2.exe, 7z.exe, MATLAB Python bridge
%     (none) → pass-through (returns srcPath unchanged)
%
%   If multiple backends are present, the first available wins (bzip2 > 7z >
%   python). The Python backend uses py.bz2.decompress, which ships with the
%   Python standard library — works on any machine where pyenv is configured.

arguments
    srcPath (1,1) string {mustBeFile}
    opts.OutDir (1,1) string = ""
    opts.Force (1,1) logical = false
end

if endsWith(srcPath, ".gz", IgnoreCase=true)
    outPath = decompressGz(srcPath, opts.OutDir, opts.Force);
elseif endsWith(srcPath, ".bz2", IgnoreCase=true)
    outPath = decompressBz2(srcPath, opts.OutDir, opts.Force);
else
    outPath = srcPath;
end
end

% ---------- gz ------------------------------------------------------------

function outPath = decompressGz(srcPath, outDir, force)
[srcDir, name, ~] = fileparts(srcPath);
if strlength(outDir) == 0
    outDir = srcDir;
end
outPath = fullfile(outDir, name);   % drops the .gz
if isfile(outPath) && ~force
    return
end
files = gunzip(char(srcPath), char(outDir));
outPath = string(files{1});
end

% ---------- bz2 -----------------------------------------------------------

function outPath = decompressBz2(srcPath, outDir, force)
[srcDir, name, ~] = fileparts(srcPath);   % name already has inner ext (.csv)
if strlength(outDir) == 0
    outDir = srcDir;
end
outPath = fullfile(outDir, name);
if isfile(outPath) && ~force
    return
end
if ~isfolder(outDir)
    mkdir(outDir);
end

[backend, exePath] = pickBz2Backend();
switch backend
    case "bzip2"
        runBzip2Exe(exePath, srcPath, outPath);
    case "7z"
        run7zExe(exePath, srcPath, outDir);
    case "python"
        runPython(srcPath, outPath);
    otherwise
        error("ice:ftp:decompress:NoBz2Backend", ...
            ['No bzip2 decoder available. Install bzip2.exe or 7-Zip, ' ...
             'or configure pyenv to point at a working Python (3.x ships ' ...
             'bz2 in the standard library).']);
end

if ~isfile(outPath)
    error("ice:ftp:decompress:Failed", ...
        "Decompression produced no file at %s (backend=%s)", outPath, backend);
end
end

function [b, exePath] = pickBz2Backend()
%PICKBZ2BACKEND Resolve the best bz2 decoder.
%   Tries in order:
%     1. bzip2 on PATH                       — fastest, native
%     2. bzip2.exe bootstrapped under cacheRoot/bin (Windows auto-install)
%     3. 7z on PATH                          — fallback
%     4. MATLAB Python bridge (py.bz2)       — last-resort, slow
persistent cachedBackend cachedPath
if ~isempty(cachedBackend)
    b = cachedBackend;
    exePath = cachedPath;
    return
end

if hasExe("bzip2")
    b = "bzip2"; exePath = "bzip2";
elseif ispc
    % Try the bootstrap path. ensureBzip2 downloads if missing.
    try
        exePath = ice.util.ensureBzip2();
        b = "bzip2";
    catch
        exePath = "";
        b = "";
    end
    if b == ""
        if hasExe("7z")
            b = "7z"; exePath = "7z";
        elseif pythonReady()
            b = "python"; exePath = "";
        end
    end
elseif hasExe("7z")
    b = "7z"; exePath = "7z";
elseif pythonReady()
    b = "python"; exePath = "";
else
    b = ""; exePath = "";
end
cachedBackend = b;
cachedPath = exePath;
end

function tf = hasExe(name)
[status, ~] = system("where " + name + " 2>nul");
tf = status == 0;
end

function tf = pythonReady()
try
    pe = pyenv;
    tf = strlength(string(pe.Executable)) > 0;
catch
    tf = false;
end
end

function runBzip2Exe(exePath, srcPath, outPath)
% bzip2 -dk keeps source, decompresses to <name> next to it.
tmp = string(tempname()) + ".bz2";
copyfile(srcPath, tmp);
cleanupTmp = onCleanup(@() safeDelete(tmp));
[status, msg] = system(sprintf('"%s" -dk "%s"', exePath, tmp));
if status ~= 0
    error("ice:ftp:decompress:Bzip2Failed", "bzip2 returned %d: %s", status, msg);
end
produced = extractBefore(tmp, ".bz2");
movefile(produced, outPath);
end

function run7zExe(exePath, srcPath, outDir)
[status, msg] = system(sprintf('"%s" e -y -o"%s" "%s"', exePath, outDir, srcPath));
if status ~= 0
    error("ice:ftp:decompress:SevenZipFailed", "7z returned %d: %s", status, msg);
end
end

function runPython(srcPath, outPath)
% py.bz2.decompress reads bytes -> bytes; safe for files up to available RAM.
% FTPSEDOL is ~24 MB compressed, well under that. For larger streams we'd
% switch to py.bz2.open + chunked read, but it's not needed yet.
data = py.bz2.decompress(py.bytes(py.open(srcPath, "rb").read()));
fid = fopen(outPath, "wb");
if fid == -1
    error("ice:ftp:decompress:OpenForWrite", "Cannot open %s for writing", outPath);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint8(data));
end

function safeDelete(p)
if isfile(p); try; delete(p); catch; end; end %#ok<NOSEMI>
end
