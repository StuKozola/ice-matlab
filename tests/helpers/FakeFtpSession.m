classdef FakeFtpSession < handle
    %FakeFtpSession Test double for ice.ftp.FtpSession.
    %   Listings come from a struct(map) of remotePath -> string array.
    %   Downloads are no-ops since tests pre-populate the cache directory.

    properties
        Listings struct
        DownloadCalls (1,:) string = strings(0)
    end

    methods
        function obj = FakeFtpSession(listings)
            arguments
                listings struct = struct()
            end
            obj.Listings = listings;
        end

        function names = list(obj, remotePath)
            arguments
                obj
                remotePath (1,1) string = "."
            end
            key = matlab.lang.makeValidName(char(remotePath));
            if isfield(obj.Listings, key)
                names = obj.Listings.(key);
            else
                names = strings(0);
            end
        end

        function localPath = download(obj, remoteFile, ~)
            obj.DownloadCalls(end+1) = string(remoteFile); %#ok<AGROW>
            localPath = "";
        end

        function close(~)
        end

        function delete(~)
        end
    end
end
