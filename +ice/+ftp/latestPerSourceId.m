function chosen = latestPerSourceId(filenames, product)
%LATESTPERSOURCEID Pick the newest dated file per source ID from a listing.
%   Filters `filenames` to entries matching the dated FTP naming convention
%   for the given product, groups by source ID, and returns one filename
%   per group — the one with the largest yyyymmdd date.
%
%   Supported products: "FTPCSD", "FTPSEDOL" (any PUB), "EODD".
%
%   Filename patterns recognised:
%       FTPCSD_PUB<n>_<srcid>_<yyyymmdd>.csv.bz2
%       FTPCSD_<srcid>_<yyyymmdd>.csv.gz           (legacy)
%       FTPSEDOL_PUB<n>_<yyyymmdd>.csv.bz2         (single srcid implied)
%       EODD_PUB<n>_<srcid>-<ent>_<yyyymmdd>.csv.gz

arguments
    filenames (1,:) string
    product   (1,1) string
end

switch upper(product)
    case "FTPCSD"
        pattern = "^FTPCSD(?:_PUB\d+)?_(?<srcid>\d+)_(?<date>\d{8})\.csv\.(?:bz2|gz)$";
    case "FTPSEDOL"
        % Filename has no srcid; group all of them under "all" so we still
        % pick the single newest entry.
        pattern = "^FTPSEDOL_PUB\d+_(?<date>\d{8})\.csv\.(?:bz2|gz)$";
    case "EODD"
        pattern = "^EODD_PUB\d+_(?<srcid>\d+)(?:-\d+)?_(?<date>\d{8})\.csv\.(?:bz2|gz)$";
    otherwise
        error("ice:ftp:latestPerSourceId:UnknownProduct", ...
            "Unknown product '%s'.", product);
end

m = regexp(filenames, pattern, "names", "once");
% regexp returns a struct for scalar input, cell for vector input; normalize.
if ~iscell(m)
    m = {m};
end
keep = ~cellfun(@isempty, m);
filenames = filenames(keep);
m = vertcat(m{keep});

if isempty(m)
    chosen = strings(0);
    return
end

% Build the grouping key. FTPSEDOL has no srcid; use a constant.
if isfield(m, "srcid")
    keys = string({m.srcid}).';
else
    keys = repmat("all", numel(m), 1);
end
dates = string({m.date}).';

% Find newest per group. Date is yyyymmdd, lex-sortable.
[uniqKeys, ~, ic] = unique(keys);
chosen = strings(numel(uniqKeys), 1);
for k = 1:numel(uniqKeys)
    inGroup = find(ic == k);
    [~, order] = sort(dates(inGroup), "descend");
    chosen(k) = filenames(inGroup(order(1)));
end
chosen = sort(chosen);
end
