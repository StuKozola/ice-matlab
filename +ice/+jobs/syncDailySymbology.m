function summary = syncDailySymbology(opts)
%SYNCDAILYSYMBOLOGY Fetch latest FTPCSD (all srcIDs) + FTPSEDOL PUB5, rebuild SymbolCache.
%
%   Designed for Windows Task Scheduler:
%     matlab -batch "ice.jobs.syncDailySymbology"
%
%   - Acquires a file lock at <cacheRoot>/.lock so concurrent runs can't
%     collide (4 h stale timeout).
%   - Connects via ice.ftp.FtpSession (default opportunistic-TLS FTP).
%   - Enumerates FTPCSD/PUB1, picks the newest dated file per srcID.
%   - Enumerates FTPSEDOL/PUB5, picks the newest dated file.
%   - Skips downloads whose canonical local path already exists (cache hit).
%   - Downloads missing files in parallel via parfeval when a pool is
%     available (default 4 workers); falls back to serial otherwise.
%   - Rebuilds the SymbolCache from ALL cached source IDs and persists the
%     parquet snapshot.
%   - Emits structured JSON events to <cacheRoot>/logs/YYYY-MM-DD.log.
%   - Any error propagates so MATLAB -batch exits with a nonzero code.

arguments
    opts.Workers (1,1) double {mustBePositive,mustBeInteger} = 4
    opts.SedolPub (1,1) double {mustBeInteger} = 5
    opts.SymbologyDir (1,1) string = "FTPCSD/PUB1"
    opts.Force (1,1) logical = false
    opts.SkipParallel (1,1) logical = false
    opts.SessionFactory function_handle = @() ice.ftp.FtpSession()
end

started = datetime("now");
ice.util.log("sync_start", struct( ...
    "workers", opts.Workers, ...
    "sedolPub", opts.SedolPub, ...
    "symbologyDir", opts.SymbologyDir, ...
    "force", opts.Force));

cache = ice.util.Cache();
lockPath = fullfile(cache.Root, ".lock");
lock = ice.util.FileLock(lockPath); %#ok<NASGU>

session = opts.SessionFactory();
sessionCleanup = onCleanup(@() session.close()); %#ok<NASGU>

% --- enumerate FTPCSD/PUB1 ----------------------------------------------
csdAll = session.list(opts.SymbologyDir);
csdLatest = ice.ftp.latestPerSourceId(csdAll, "FTPCSD");
ice.util.log("sync_enum_csd", struct( ...
    "total", numel(csdAll), ...
    "latestPerSrc", numel(csdLatest)));

% --- enumerate FTPSEDOL/PUBn --------------------------------------------
sedDir = sprintf("FTPSEDOL/PUB%d", opts.SedolPub);
sedAll = session.list(sedDir);
sedLatest = ice.ftp.latestPerSourceId(sedAll, "FTPSEDOL");
if isempty(sedLatest)
    error("ice:jobs:syncDailySymbology:NoSedolFile", ...
        "No FTPSEDOL_PUB%d_<date>.csv.bz2 file found in %s", opts.SedolPub, sedDir);
end
ice.util.log("sync_enum_sedol", struct( ...
    "total", numel(sedAll), ...
    "selected", sedLatest));

% --- build the work list ------------------------------------------------
csdRemote   = opts.SymbologyDir + "/" + csdLatest;
sedolRemote = sedDir + "/" + sedLatest;
allRemote   = [csdRemote(:); sedolRemote];

% Skip files already cached (unless Force).
localPaths = strings(size(allRemote));
toFetch = false(size(allRemote));
for k = 1:numel(allRemote)
    [~, base, ext] = fileparts(allRemote(k));
    localPaths(k) = cache.rawPath(base + ext);
    toFetch(k) = opts.Force || ~isfile(localPaths(k));
end
ice.util.log("sync_plan", struct( ...
    "totalFiles", numel(allRemote), ...
    "alreadyCached", sum(~toFetch), ...
    "toDownload", sum(toFetch)));

% --- download missing ---------------------------------------------------
fetchRemote = allRemote(toFetch);
if ~isempty(fetchRemote)
    downloadFiles(session, cache, fetchRemote, opts);
end

% --- locate cached FTPCSD files & rebuild symbol cache ------------------
csdLocal = strings(numel(csdLatest), 1);
for k = 1:numel(csdLatest)
    csdLocal(k) = cache.rawPath(csdLatest(k));
end
sedolLocal = cache.rawPath(sedLatest);

ice.util.log("sync_build_start", struct("ftpcsdFiles", numel(csdLocal)));
sym = ice.sym.SymbolCache();
sym.build(FtpcsdFiles=csdLocal, FtpsedolFile=sedolLocal);
masterRows = height(sym.table());
ice.util.log("sync_build_done", struct("masterRows", masterRows));

% --- summary ------------------------------------------------------------
elapsed = datetime("now") - started;
summary = struct( ...
    "csdSources", numel(csdLatest), ...
    "ftpsedolFile", sedolLocal, ...
    "downloaded", sum(toFetch), ...
    "alreadyCached", sum(~toFetch), ...
    "masterRows", masterRows, ...
    "elapsedSeconds", seconds(elapsed));
ice.util.log("sync_done", summary);
end

% --------------------------------------------------------------------------

function downloadFiles(session, cache, remoteFiles, opts)
% Parallel fetch when a pool is available; serial fallback otherwise.
useParallel = ~opts.SkipParallel && ...
    license("test", "Distrib_Computing_Toolbox") && ...
    canStartPool(opts.Workers);

if useParallel
    fetchInParallel(session, cache, remoteFiles, opts);
else
    fetchSerial(session, cache, remoteFiles);
end
end

function fetchSerial(session, cache, remoteFiles)
for k = 1:numel(remoteFiles)
    fetchOne(session, cache, remoteFiles(k));
end
end

function fetchInParallel(~, cache, remoteFiles, opts)
% Each worker creates its own FtpSession — handle objects can't be shared
% across workers by reference, and reusing one session would also serialise
% on its internal mutex. Process workers are safer than thread workers for
% MATLAB's ftp() object.
pool = gcp("nocreate");
if isempty(pool)
    pool = parpool("Processes", opts.Workers);  %#ok<NASGU>
    pool = gcp("nocreate");
end
if isempty(pool) || pool.NumWorkers < 1
    fetchSerial(ice.ftp.FtpSession(), cache, remoteFiles);
    return
end

% Resolve credentials in the client and pass them explicitly; worker
% MATLAB instances may not see the same Vault entries or .env file the
% client used.
user = ice.config.credentials("ICE_FTP_USER");
pwd  = ice.config.credentials("ICE_FTP_PWD");
cacheRoot = cache.Root;

futures(numel(remoteFiles)) = parallel.FevalFuture();
for k = 1:numel(remoteFiles)
    futures(k) = parfeval(pool, @workerFetch, 0, ...
        remoteFiles(k), cacheRoot, user, pwd);
end
wait(futures);
for k = 1:numel(futures)
    if ~isempty(futures(k).Error)
        rethrow(futures(k).Error);
    end
end
end

function workerFetch(remoteFile, cacheRoot, user, pwd)
session = ice.ftp.FtpSession(Username=user, Password=pwd, ...
    SuppressCleartextWarning=true);
cache = ice.util.Cache(cacheRoot);
try
    fetchOne(session, cache, remoteFile);
catch err
    session.close();
    rethrow(err);
end
session.close();
end

function fetchOne(session, cache, remoteFile)
[~, base, ext] = fileparts(remoteFile);
localPath = cache.rawPath(base + ext);
if isfile(localPath)
    return
end
ice.ftp.download(session, remoteFile, Cache=cache);
end

function tf = canStartPool(workers)
try
    p = gcp("nocreate");
    if ~isempty(p) && p.NumWorkers >= 1
        tf = true;
        return
    end
    parpool("Processes", workers);
    tf = true;
catch
    tf = false;
end
end
