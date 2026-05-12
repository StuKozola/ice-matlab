function tbl = parseOptionsXml(xml)
%PARSEOPTIONSXML Convert /options XML to a long-format chain table.
%   Root is <options ...> with one or more <option> children. Each
%   <option> carries chain-level metadata (strike, underlier, root,
%   exchg, dte/dtetd) and exactly one <call> and one <put> child with
%   the per-side quote fields (recent, bid, ask, oldsettle, openint, ...).
%
%   Output: one row per (strike, side). Chain-level metadata is repeated
%   on both rows. The "side" column is "call" or "put". Missing per-side
%   fields become NaN (numeric) or <missing> (string).
%
%   /options shares the /quote error envelopes: <xcpt n="..."/>, an
%   <options status="error ..."/> envelope, or status="error" attributes
%   on individual <option> elements. The first two raise; the third
%   propagates as a status column on the affected rows.

arguments
    xml (1,1) string
end

xml = strip(xml);
if hasException(xml)
    raiseFromException(xml);
end
% /options root-level error envelope, same shape as flexhistory.
statusErr = regexp(xml, '<options[^>]*\sstatus="(error[^"]*)"', "tokens", "once");
if ~isempty(statusErr)
    msg = string(statusErr{1});
    if startsWith(msg, "error code: -15")
        error("ice:api:NotEntitled", "ICE refused the options request: %s", msg);
    end
    error("ice:api:ResponseError", "options request failed: %s", msg);
end

tmp = string(tempname()) + ".xml";
fid = fopen(tmp, "w", "n", "UTF-8");
cleanup = onCleanup(@() safeDelete(tmp));
fwrite(fid, uint8(char(xml)));
fclose(fid);

s = readstruct(tmp, FileType="xml");

if ~isfield(s, "option")
    tbl = table();
    return
end

options = s.option;
nOpt = numel(options);

% Pass 1: discover the union of per-side field names AND decide each
% field's column type (numeric vs string) by sniffing the first
% non-missing value. Doing the type decision upfront lets pass 2 take
% a branch-free fast path per field; previously we re-decided per row
% via a containers.Map probe and burned ~30% of total time on it.
sideTypes = struct();   % field -> "num" | "str"
for k = 1:nOpt
    o = options(k);
    for side_i = ["call", "put"]
        if ~isfield(o, side_i); continue; end
        ce = o.(side_i);
        if isempty(ce) || all(ismissing(ce)); continue; end
        if numel(ce) > 1; ce = ce(1); end
        fn = string(fieldnames(ce));
        fn = fn(~endsWith(fn, "Attribute") & fn ~= "Text");
        for j = 1:numel(fn)
            f = fn(j);
            if isfield(sideTypes, f); continue; end
            kind = sniffType(ce.(f));
            if kind ~= ""
                sideTypes.(f) = kind;
            end
        end
    end
end
sideFieldSet = string(fieldnames(sideTypes));

% Chain-level metadata columns (string for safety; strike is numeric).
metaStrCols = ["underlier","root","exchg","type","status","request","id"];
metaNumCols = ["strike","dte","dtetd","units","unitssecondary","delay"];

rowsPerOpt = 2;
nRows = nOpt * rowsPerOpt;

side = strings(nRows, 1);
metaStr = struct();
for c = 1:numel(metaStrCols); metaStr.(metaStrCols(c)) = strings(nRows, 1); end
metaNum = struct();
for c = 1:numel(metaNumCols); metaNum.(metaNumCols(c)) = nan(nRows, 1); end

% Pre-allocate per-side columns with their known types.
sideStr = struct();
sideNum = struct();
sideIsNum = false(numel(sideFieldSet), 1);
for c = 1:numel(sideFieldSet)
    f = sideFieldSet(c);
    if sideTypes.(f) == "num"
        sideNum.(f) = nan(nRows, 1);
        sideIsNum(c) = true;
    else
        sideStr.(f) = strings(nRows, 1);
    end
end

idx = 0;
for k = 1:nOpt
    o = options(k);
    for side_i = ["call", "put"]
        idx = idx + 1;
        side(idx) = side_i;
        for c = 1:numel(metaStrCols)
            metaStr.(metaStrCols(c))(idx) = readMetaString(o, metaStrCols(c));
        end
        for c = 1:numel(metaNumCols)
            metaNum.(metaNumCols(c))(idx) = readMetaNumeric(o, metaNumCols(c));
        end

        if ~isfield(o, side_i); continue; end
        ce = o.(side_i);
        if isempty(ce) || all(ismissing(ce)); continue; end
        if numel(ce) > 1; ce = ce(1); end

        for c = 1:numel(sideFieldSet)
            f = sideFieldSet(c);
            if ~isfield(ce, f); continue; end
            raw = ce.(f);
            if isstruct(raw)
                if isscalar(raw) && isfield(raw, "Text") && ~ismissing(raw.Text)
                    raw = raw.Text;
                else
                    continue;
                end
            end
            if all(ismissing(raw)); continue; end
            if sideIsNum(c)
                if isnumeric(raw)
                    sideNum.(f)(idx) = double(raw);
                else
                    d = str2double(string(raw));
                    if ~isnan(d); sideNum.(f)(idx) = d; end
                end
            else
                sideStr.(f)(idx) = string(raw);
            end
        end
    end
end

tbl = table();
for c = 1:numel(metaStrCols); tbl.(metaStrCols(c)) = metaStr.(metaStrCols(c)); end
for c = 1:numel(metaNumCols); tbl.(metaNumCols(c)) = metaNum.(metaNumCols(c)); end
tbl.side = side;

sideFieldSorted = sort(sideFieldSet);
for c = 1:numel(sideFieldSorted)
    f = sideFieldSorted(c);
    if sideTypes.(f) == "num"
        tbl.(f) = sideNum.(f);
    else
        tbl.(f) = sideStr.(f);
    end
end
end

function kind = sniffType(raw)
% Returns "num" | "str" | "" (the latter means "don't know yet").
kind = "";
if isstruct(raw)
    if isscalar(raw) && isfield(raw, "Text") && ~ismissing(raw.Text)
        raw = raw.Text;
    else
        kind = "str";  % nested children -> we'll store .Text or skip
        return
    end
end
if all(ismissing(raw)); return; end
if isnumeric(raw)
    kind = "num";
    return
end
% String / char: probe with str2double.
d = str2double(string(raw));
if isnan(d) || strlength(string(raw)) == 0
    kind = "str";
else
    kind = "num";
end
end

function v = readMetaString(o, name)
% Try child element first, then "<name>Attribute". The child element may
% be either a scalar string or a struct with .Text (when the XML element
% has attributes alongside its text body, e.g. <underlier type="stock">AAPL</underlier>).
v = "";
if isfield(o, name)
    v = nodeText(o.(name));
end
if v == "" && isfield(o, name + "Attribute")
    raw = o.(name + "Attribute");
    if ~ismissing(raw); v = string(raw); end
end
end

function v = readMetaNumeric(o, name)
v = NaN;
if isfield(o, name)
    txt = nodeText(o.(name));
    if txt ~= ""; v = str2double(txt); return; end
end
if isfield(o, name + "Attribute")
    raw = o.(name + "Attribute");
    if ~ismissing(raw)
        if ischar(raw) || isstring(raw)
            v = str2double(string(raw));
        elseif isnumeric(raw)
            v = double(raw);
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

function v = nodeText(raw)
% Coerce a readstruct value to its text. Plain scalars become a string;
% structs with a .Text body return that; anything else (nested children
% only, or all-missing) returns "".
v = "";
if isempty(raw) || all(ismissing(raw)); return; end
if isstruct(raw)
    if isscalar(raw) && isfield(raw, "Text") && ~ismissing(raw.Text)
        v = string(raw.Text);
    end
    return
end
v = string(raw);
if ismissing(v); v = ""; end
end
