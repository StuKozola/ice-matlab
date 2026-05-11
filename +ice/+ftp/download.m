function localPath = download(session, remoteFile, opts)
%DOWNLOAD Cache-aware atomic download of a remote ICE FTP file.
%   path = ice.ftp.download(session, "FTPSEDOL/PUB2/FTPSEDOL_PUB2_20240213.csv.bz2")
%
%   Stores the file under <cacheRoot>/ftp_raw/<basename>. If a file with that
%   name already exists locally, returns immediately (Force=true to refetch).
%   The actual transfer goes through FtpSession.download, which writes to a
%   .part file and renames atomically.

arguments
    session ice.ftp.FtpSession
    remoteFile (1,1) string
    opts.Force (1,1) logical = false
    opts.Cache ice.util.Cache = ice.util.Cache.empty
end

if isempty(opts.Cache)
    cache = ice.util.Cache();
else
    cache = opts.Cache;
end

[~, name, ext] = fileparts(remoteFile);
basename = name + ext;
localPath = cache.rawPath(basename);

if isfile(localPath) && ~opts.Force
    return
end

session.download(remoteFile, fileparts(localPath));
end
