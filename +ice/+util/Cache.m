classdef Cache < handle
    %Cache Local on-disk cache rooted at ice.config.cacheRoot().
    %   Three tiers:
    %     rawPath(name)         -> data/ftp_raw/<name>   (untouched downloads)
    %     parquetPath(srcid, d) -> data/parquet/srcid=.../date=.../
    %     get/put(key, value)   -> data/kv/<sha1(key)>.mat

    properties (SetAccess = immutable)
        Root (1,1) string
    end

    methods
        function obj = Cache(root)
            arguments
                root (1,1) string = ""
            end
            if strlength(root) == 0
                obj.Root = ice.config.cacheRoot();
            else
                obj.Root = ice.config.cacheRoot(root);
            end
        end

        function p = rawPath(obj, name)
            arguments
                obj
                name (1,1) string
            end
            p = fullfile(obj.Root, "ftp_raw", name);
        end

        function p = parquetPath(obj, srcid, dateStr)
            arguments
                obj
                srcid (1,1) string
                dateStr (1,1) string
            end
            p = fullfile(obj.Root, "parquet", "srcid=" + srcid, "date=" + dateStr);
            if ~isfolder(p)
                mkdir(p);
            end
        end

        function tf = hasRaw(obj, name)
            tf = isfile(obj.rawPath(name));
        end

        function put(obj, key, value)
            arguments
                obj
                key (1,1) string
                value
            end
            kvDir = fullfile(obj.Root, "kv");
            if ~isfolder(kvDir)
                mkdir(kvDir);
            end
            file = fullfile(kvDir, obj.hashKey(key) + ".mat");
            save(file, "value", "key", "-v7");
        end

        function [value, hit] = get(obj, key)
            arguments
                obj
                key (1,1) string
            end
            file = fullfile(obj.Root, "kv", obj.hashKey(key) + ".mat");
            if isfile(file)
                s = load(file);
                value = s.value;
                hit = true;
            else
                value = [];
                hit = false;
            end
        end
    end

    methods (Static, Access = private)
        function h = hashKey(key)
            md = java.security.MessageDigest.getInstance("SHA-1");
            bytes = md.digest(uint8(char(key)));
            h = string(lower(reshape(dec2hex(typecast(bytes, "uint8"), 2).', 1, [])));
        end
    end
end
