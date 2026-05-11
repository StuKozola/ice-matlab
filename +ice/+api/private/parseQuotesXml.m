function tbl = parseQuotesXml(xml)
%PARSEQUOTESXML Convert /quote (or /options) XML to a table.
%   Root is <quotes request="..." retrieved="..."> containing one or more
%   <quote status="ok|unknown" request="..." id="..." delay="..."> nodes.
%   Each quote has zero-or-more typed child elements (recent, bid, ask, ...).
%
%   We materialize the union of all field names across the rows so callers
%   get a single table; missing fields become NaN (numeric) or <missing>
%   (string).

arguments
    xml (1,1) string
end

xml = strip(xml);
if hasException(xml)
    raiseFromException(xml);
end

tmp = string(tempname()) + ".xml";
fid = fopen(tmp, "w", "n", "UTF-8");
cleanup = onCleanup(@() safeDelete(tmp));
fwrite(fid, uint8(char(xml)));
fclose(fid);

s = readstruct(tmp, FileType="xml");

if ~isfield(s, "quote")
    tbl = table();
    return
end

quotes = s.quote;
n = numel(quotes);

% Pre-collect every distinct child field across the response.
fieldSet = ["status","request","id","delay"];   % attributes we always materialize
valueFields = string([]);
for k = 1:n
    fn = string(fieldnames(quotes(k)));
    fn = fn(~endsWith(fn, "Attribute"));
    valueFields = unique([valueFields; fn]);
end
fieldSet = [fieldSet, valueFields.'];

% Build the table column-by-column.
cols = cell(1, numel(fieldSet));
for c = 1:numel(fieldSet)
    name = fieldSet(c);
    cols{c} = collectColumn(quotes, name);
end

tbl = table(cols{:}, VariableNames=fieldSet);
end

function v = collectColumn(quotes, name)
n = numel(quotes);
isAttr = ismember(name, ["status","request","id","delay"]);

if isAttr
    v = strings(n, 1);
    attrField = name + "Attribute";
    for k = 1:n
        if isfield(quotes(k), attrField)
            raw = quotes(k).(attrField);
            if ~ismissing(raw); v(k) = string(raw); end
        end
    end
    return
end

% Sniff first non-missing value to pick numeric vs string column.
isNumeric = true;
for k = 1:n
    if isfield(quotes(k), name)
        raw = quotes(k).(name);
        if ~ismissing(raw)
            if ischar(raw) || isstring(raw)
                if isnan(str2double(string(raw)))
                    isNumeric = false;
                end
            elseif ~isnumeric(raw)
                isNumeric = false;
            end
            break;
        end
    end
end

if isNumeric
    v = nan(n, 1);
    for k = 1:n
        if isfield(quotes(k), name)
            raw = quotes(k).(name);
            if ~ismissing(raw)
                if ischar(raw) || isstring(raw)
                    v(k) = str2double(string(raw));
                else
                    v(k) = double(raw);
                end
            end
        end
    end
else
    v = strings(n, 1);
    for k = 1:n
        if isfield(quotes(k), name)
            raw = quotes(k).(name);
            if ~ismissing(raw); v(k) = string(raw); end
        end
    end
end
end

function raiseFromException(xml)
msg = regexp(xml, '<xcpt[^>]*n="([^"]*)"', "tokens", "once");
if isempty(msg)
    msg = regexp(xml, '<exception>([^<]*)</exception>', "tokens", "once");
end
if isempty(msg)
    error("ice:api:ResponseError", "Server returned an error: %s", xml);
end
error("ice:api:ResponseError", "Server returned an error: %s", string(msg{1}));
end

function tf = hasException(xml)
tf = contains(xml, "<xcpt") || ...
     ~isempty(regexp(xml, '<exception\b', "once"));
end

function safeDelete(p)
if isfile(p); try; delete(p); catch; end; end %#ok<NOSEMI>
end
