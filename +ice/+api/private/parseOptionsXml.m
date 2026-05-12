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

% First pass: collect the union of per-side quote field names across all
% calls and puts so every row has the same column set.
sideFieldSet = string([]);
for k = 1:nOpt
    o = options(k);
    if isfield(o, "call")
        sideFieldSet = unique([sideFieldSet; sideFieldNames(o.call)]);
    end
    if isfield(o, "put")
        sideFieldSet = unique([sideFieldSet; sideFieldNames(o.put)]);
    end
end

% Chain-level metadata columns (string for safety; strike is numeric).
metaStrCols = ["underlier","root","exchg","type","status","request","id"];
metaNumCols = ["strike","dte","dtetd","units","unitssecondary","delay"];

rowsPerOpt = 2;  % call + put, even if one side missing (we emit a missing row)
nRows = nOpt * rowsPerOpt;

% Allocate columns.
side = strings(nRows, 1);
metaStr = struct();
for c = 1:numel(metaStrCols); metaStr.(metaStrCols(c)) = strings(nRows, 1); end
metaNum = struct();
for c = 1:numel(metaNumCols); metaNum.(metaNumCols(c)) = nan(nRows, 1); end
sideStr = struct();
sideNum = struct();
sideKindNumeric = containers.Map('KeyType','char','ValueType','logical');

idx = 0;
for k = 1:nOpt
    o = options(k);
    for side_i = ["call", "put"]
        idx = idx + 1;
        side(idx) = side_i;
        % Chain-level metadata: prefer child elements (stock-options shape),
        % fall back to attributes (future-options shape uses some attrs).
        for c = 1:numel(metaStrCols)
            metaStr.(metaStrCols(c))(idx) = readMetaString(o, metaStrCols(c));
        end
        for c = 1:numel(metaNumCols)
            metaNum.(metaNumCols(c))(idx) = readMetaNumeric(o, metaNumCols(c));
        end

        % Per-side fields: pull from the o.call / o.put child if present.
        if isfield(o, char(side_i)) && ~isempty(o.(char(side_i))) && ~all(ismissing(o.(char(side_i))))
            ce = o.(char(side_i));
            % If multiple call/put nodes for a given option (shouldn't happen
            % per docs, but be defensive), take the first.
            if numel(ce) > 1; ce = ce(1); end
            for c = 1:numel(sideFieldSet)
                fld = sideFieldSet(c);
                [val, isNum] = readSideField(ce, fld);
                if ~isKey(sideKindNumeric, char(fld))
                    sideKindNumeric(char(fld)) = isNum;
                    if isNum
                        sideNum.(fld) = nan(nRows, 1);
                    else
                        sideStr.(fld) = strings(nRows, 1);
                    end
                end
                if sideKindNumeric(char(fld))
                    if ~isfield(sideNum, fld); sideNum.(fld) = nan(nRows, 1); end
                    if isnumeric(val) && ~isnan(val); sideNum.(fld)(idx) = val; end
                else
                    if ~isfield(sideStr, fld); sideStr.(fld) = strings(nRows, 1); end
                    if isnumeric(val); continue; end  % field missing on this row
                    if val ~= ""; sideStr.(fld)(idx) = val; end %#ok<STCMP>
                end
            end
        end
    end
end

% Assemble: meta columns, then side, then per-side fields in alphabetical order.
tbl = table();
for c = 1:numel(metaStrCols); tbl.(metaStrCols(c)) = metaStr.(metaStrCols(c)); end
for c = 1:numel(metaNumCols); tbl.(metaNumCols(c)) = metaNum.(metaNumCols(c)); end
tbl.side = side;

sideFieldSorted = sort(sideFieldSet);
for c = 1:numel(sideFieldSorted)
    fld = sideFieldSorted(c);
    if isKey(sideKindNumeric, char(fld)) && sideKindNumeric(char(fld))
        tbl.(fld) = sideNum.(fld);
    else
        if isfield(sideStr, fld)
            tbl.(fld) = sideStr.(fld);
        else
            tbl.(fld) = strings(nRows, 1);
        end
    end
end
end

function names = sideFieldNames(node)
% Names of value-bearing children on a <call> or <put>. Filters out the
% XML attribute placeholders (*Attribute) and the readstruct synthetic
% "Text" field used when an element has both attributes and a text body.
if isempty(node) || all(ismissing(node))
    names = string([]);
    return
end
if numel(node) > 1; node = node(1); end
fn = string(fieldnames(node));
names = fn(~endsWith(fn, "Attribute") & fn ~= "Text");
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

function [val, isNum] = readSideField(node, name)
isNum = true;
val = NaN;
if ~isfield(node, name); return; end
raw = node.(name);
% Struct-shaped node (attributes alongside text, or nested children) —
% take .Text if present; otherwise skip this field for this row.
if isstruct(raw)
    if isscalar(raw) && isfield(raw, "Text") && ~ismissing(raw.Text)
        raw = raw.Text;
    else
        isNum = false;
        val = "";
        return
    end
end
if all(ismissing(raw)); return; end
if ischar(raw) || isstring(raw)
    d = str2double(string(raw));
    if isnan(d)
        isNum = false;
        val = string(raw);
    else
        val = d;
    end
elseif isnumeric(raw)
    val = double(raw);
else
    isNum = false;
    val = string(raw);
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
