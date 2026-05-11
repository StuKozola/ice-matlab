function root = cacheRoot(override)
arguments
    override (1,1) string = ""
end

if strlength(override) > 0
    root = override;
elseif strlength(string(getenv("ICE_CACHE_ROOT"))) > 0
    root = string(getenv("ICE_CACHE_ROOT"));
elseif exist("ice.config.local", "file") == 2
    root = string(ice.config.local());
else
    root = fullfile(toolboxRoot(), "data");
end

root = string(root);
if ~isfolder(root)
    mkdir(root);
end
for sub = ["ftp_raw", "parquet", "logs"]
    p = fullfile(root, sub);
    if ~isfolder(p)
        mkdir(p);
    end
end
end

function r = toolboxRoot()
here = fileparts(mfilename("fullpath"));
r = fileparts(fileparts(here));
end
