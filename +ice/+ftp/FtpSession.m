classdef FtpSession < handle
    %FtpSession Resilient connection to the ICE EOD servers.
    %   ICE production hosts (eod11/eod12/eod13) accept plain FTP on port 21
    %   only; SFTP/22 is reserved for the developer test site
    %   (idsftp.icedataservices.com). Defaults reflect that: ftp() with
    %   TLSMode="opportunistic" so we upgrade to FTPS via AUTH TLS when the
    %   server advertises it, and fall back to cleartext when it doesn't.
    %
    %   Pass Protocol="sftp" to talk to idsftp / any SFTP host; pass
    %   TlsMode="strict" to refuse cleartext when using FTP. Hosts rotate
    %   on connect failure. Downloads land on a .part sibling and rename
    %   atomically.

    properties (SetAccess = immutable)
        Hosts (1,:) string
        Username (1,1) string
        Protocol (1,1) string = "ftp"
        TlsMode  (1,1) string = "opportunistic"
        ConnectTimeout (1,1) duration = seconds(60)
        TransferTimeout (1,1) duration = seconds(600)
        SuppressCleartextWarning (1,1) logical = false
    end

    properties (Access = private)
        Conn
        ActiveHost (1,1) string = ""
        Password (1,1) string = ""
    end

    methods
        function obj = FtpSession(opts)
            arguments
                opts.Protocol (1,1) string {mustBeMember(opts.Protocol, ["ftp","sftp"])} = "ftp"
                opts.Hosts (1,:) string = string.empty
                opts.TlsMode (1,1) string {mustBeMember(opts.TlsMode, ["none","opportunistic","strict"])} = "opportunistic"
                opts.Username (1,1) string = ice.config.credentials("ICE_FTP_USER")
                opts.Password (1,1) string = ice.config.credentials("ICE_FTP_PWD")
                opts.ConnectTimeout (1,1) duration = seconds(60)
                opts.TransferTimeout (1,1) duration = seconds(600)
                opts.SuppressCleartextWarning (1,1) logical = false
            end
            obj.Protocol = opts.Protocol;
            obj.SuppressCleartextWarning = opts.SuppressCleartextWarning;
            if isempty(opts.Hosts)
                opts.Hosts = defaultHostsFor(obj.Protocol);
            end
            obj.Hosts = opts.Hosts;
            obj.Username = opts.Username;
            obj.Password = opts.Password;
            obj.TlsMode = opts.TlsMode;
            obj.ConnectTimeout = opts.ConnectTimeout;
            obj.TransferTimeout = opts.TransferTimeout;
            obj.connect();
        end

        function names = list(obj, remotePath)
            arguments
                obj
                remotePath (1,1) string = "."
            end
            obj.ensureConnected();
            entries = obj.listDetailed(remotePath);
            if isempty(entries)
                names = strings(0);
            else
                names = string({entries.name});
            end
        end

        function entries = listDetailed(obj, remotePath)
            %LISTDETAILED Return struct array of remote entries (name, bytes, isdir).
            %   Bypasses MATLAB's dir() symlink-replacement step (which crashes
            %   on real ICE FTPCSD/ listings) by requesting the raw LIST
            %   output with ParseOutput=false and parsing it locally with our
            %   tolerant parser.
            arguments
                obj
                remotePath (1,1) string = "."
            end
            obj.ensureConnected();
            if obj.Protocol == "sftp"
                d = dir(obj.Conn, char(remotePath));
            else
                rawLines = dir(obj.Conn, char(remotePath), ParseOutput=false);
                d = ice.ftp.FtpSession.tolerantDirParser(rawLines, obj.Conn.ServerLocale);
            end
            if isempty(d)
                entries = struct("name", {}, "bytes", {}, "isdir", {}, ...
                                 "date", {}, "datenum", {});
            else
                entries = d;
            end
        end

        function localPath = download(obj, remoteFile, localDir)
            %DOWNLOAD Download a remote file atomically into localDir.
            %   The file is fetched to a uniquely-named .part sibling and
            %   renamed onto the final name on success, so a killed transfer
            %   never leaves a corrupt cached file at the canonical path.
            arguments
                obj
                remoteFile (1,1) string
                localDir (1,1) string
            end
            obj.ensureConnected();
            if ~isfolder(localDir)
                mkdir(localDir);
            end
            [~, name, ext] = fileparts(remoteFile);
            finalPath = fullfile(localDir, name + ext);
            partPath  = finalPath + ".part." + string(feature("getpid"));

            partDir = fileparts(partPath);
            if ~isfolder(partDir); mkdir(partDir); end

            ice.util.log("ftp_download_start", struct( ...
                "host", obj.ActiveHost, ...
                "remote", remoteFile, ...
                "local", finalPath), Echo=false);

            saved = mget(obj.Conn, char(remoteFile), char(partDir));
            % mget saves under the original filename inside partDir.
            stagedPath = string(saved{1});
            movefile(stagedPath, finalPath);
            localPath = finalPath;

            ice.util.log("ftp_download_done", struct( ...
                "host", obj.ActiveHost, ...
                "local", finalPath, ...
                "bytes", dir(finalPath).bytes), Echo=false);
        end

        function host = activeHost(obj)
            host = obj.ActiveHost;
        end

        function close(obj)
            if ~isempty(obj.Conn)
                try; close(obj.Conn); catch; end %#ok<NOSEMI>
                obj.Conn = [];
                obj.ActiveHost = "";
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function connect(obj)
            lastErr = MException.empty;
            for h = obj.Hosts
                try
                    if obj.Protocol == "sftp"
                        obj.Conn = sftp(char(h), char(obj.Username), ...
                            Password=char(obj.Password), ...
                            ConnectionTimeout=obj.ConnectTimeout, ...
                            TransferTimeout=obj.TransferTimeout);
                    else
                        obj.Conn = ftp(char(h), char(obj.Username), char(obj.Password), ...
                            TLSMode=char(obj.TlsMode), ...
                            ConnectionTimeout=obj.ConnectTimeout, ...
                            TransferTimeout=obj.TransferTimeout);
                    end
                    obj.ActiveHost = h;
                    ice.util.log("ftp_connect_ok", ...
                        struct("host", h, "user", obj.Username, ...
                               "protocol", obj.Protocol, ...
                               "tlsMode", obj.TlsMode));
                    if obj.Protocol == "ftp" && obj.TlsMode ~= "strict" ...
                            && ~obj.SuppressCleartextWarning
                        ice.util.log("ftp_cleartext_warning", ...
                            struct("host", h, ...
                                   "note", ['Session may be cleartext: ICE prod hosts ' ...
                                            'were observed not to advertise AUTH TLS as of 2026-05. ' ...
                                            'Pass SuppressCleartextWarning=true to silence ' ...
                                            'once you have confirmed your network path is acceptable.']), ...
                            Level="warn");
                    end
                    return
                catch err
                    lastErr = err;
                    ice.util.log("ftp_connect_fail", ...
                        struct("host", h, "id", err.identifier, ...
                               "message", err.message, ...
                               "protocol", obj.Protocol), Level="warn");
                end
            end
            error("ice:ftp:FtpSession:NoHostReachable", ...
                "Could not connect to any of: %s. Last error: %s", ...
                strjoin(obj.Hosts, ", "), lastErr.message);
        end

        function ensureConnected(obj)
            if isempty(obj.Conn)
                obj.connect();
            end
        end
    end

    methods (Static)
        function listing = tolerantDirParser(lines, ~)
            %TOLERANTDIRPARSER Permissive parser for unix-style LIST output.
            %   MATLAB's built-in parser hard-fails on any line it cannot
            %   split into exactly its expected token count, which breaks
            %   listings containing oddly-formatted entries (e.g. very long
            %   filenames or unusual date columns). This parser extracts
            %   what we need (name, size, isdir) and silently skips lines
            %   that don't look like a standard LIST entry.
            %
            %   Standard unix LIST line:
            %     -rw-r--r--  1 user group   12345 May 11 12:34 filename.csv.gz
            %     drwxr-xr-x  2 user group    4096 May 11 12:34 PUB1
            %     lrwxrwxrwx  1 user group      28 May 11 12:34 link.csv -> target.csv

            n = numel(lines);
            namesC   = cell(n,1);
            sizesC   = cell(n,1);
            isdirsC  = cell(n,1);
            datenumC = cell(n,1);
            dateC    = cell(n,1);
            kept = false(n,1);

            for k = 1:n
                line = strip(lines(k));
                if strlength(line) == 0; continue; end
                parts = strsplit(line);
                if numel(parts) < 9; continue; end   % "total NN" lines etc.
                perms = char(parts{1});
                if numel(perms) < 1; continue; end
                isDir = perms(1) == 'd';
                isLink = perms(1) == 'l';
                bytes = str2double(parts{5});
                if isnan(bytes); continue; end
                % Filename runs from token 9 to end, BUT for symlinks the
                % format is "name -> target" so we cut at " -> " if present.
                tail = strjoin(parts(9:end), " ");
                if isLink
                    arrow = strfind(tail, " -> ");
                    if ~isempty(arrow)
                        tail = extractBefore(tail, arrow(1));
                    end
                end
                name = char(strip(tail));
                if isempty(name) || any(strcmp(name, {'.', '..'})); continue; end

                kept(k) = true;
                namesC{k}   = name;
                sizesC{k}   = bytes;
                isdirsC{k}  = isDir;
                dateC{k}    = strjoin(parts(6:8), " ");
                datenumC{k} = NaN;  % MATLAB's parser also leaves this loose
            end

            keep = find(kept);
            listing = struct("name", "", "date", "", "bytes", 0, ...
                             "isdir", false, "datenum", NaN);
            listing = repmat(listing, numel(keep), 1);
            for j = 1:numel(keep)
                idx = keep(j);
                listing(j).name    = namesC{idx};
                listing(j).date    = dateC{idx};
                listing(j).bytes   = sizesC{idx};
                listing(j).isdir   = isdirsC{idx};
                listing(j).datenum = datenumC{idx};
            end
        end
    end
end

function h = defaultHostsFor(protocol)
if protocol == "sftp"
    h = "idsftp.icedataservices.com";
else
    h = ["eod11.icedataservices.com", ...
         "eod12.icedataservices.com", ...
         "eod13.icedataservices.com"];
end
end
