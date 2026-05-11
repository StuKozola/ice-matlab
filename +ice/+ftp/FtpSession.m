classdef FtpSession < handle
    %FtpSession Resilient SFTP session against the ICE FTP servers.
    %   Connects to one of eod11/eod12/eod13.icedataservices.com (rotating
    %   on connection failure), authenticates with credentials resolved by
    %   ice.config.credentials, and exposes basic listing / atomic download
    %   primitives. Closes the underlying connection when the object is
    %   destroyed.

    properties (SetAccess = immutable)
        Hosts (1,:) string
        Username (1,1) string
        ConnectTimeout (1,1) duration = seconds(60)
        TransferTimeout (1,1) duration = seconds(600)
    end

    properties (Access = private)
        Conn
        ActiveHost (1,1) string = ""
        Password (1,1) string = ""
    end

    methods
        function obj = FtpSession(opts)
            arguments
                opts.Hosts (1,:) string = ["eod11.icedataservices.com", ...
                                            "eod12.icedataservices.com", ...
                                            "eod13.icedataservices.com"]
                opts.Username (1,1) string = ice.config.credentials("ICE_FTP_USER")
                opts.Password (1,1) string = ice.config.credentials("ICE_FTP_PWD")
                opts.ConnectTimeout (1,1) duration = seconds(60)
                opts.TransferTimeout (1,1) duration = seconds(600)
            end
            obj.Hosts = opts.Hosts;
            obj.Username = opts.Username;
            obj.Password = opts.Password;
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
            d = dir(obj.Conn, char(remotePath));
            if isempty(d)
                names = strings(0);
            else
                names = string({d.name});
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
                    obj.Conn = sftp(char(h), char(obj.Username), ...
                        Password=char(obj.Password), ...
                        ConnectionTimeout=obj.ConnectTimeout, ...
                        TransferTimeout=obj.TransferTimeout);
                    obj.ActiveHost = h;
                    ice.util.log("ftp_connect_ok", ...
                        struct("host", h, "user", obj.Username));
                    return
                catch err
                    lastErr = err;
                    ice.util.log("ftp_connect_fail", ...
                        struct("host", h, "id", err.identifier, ...
                               "message", err.message), Level="warn");
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
end
