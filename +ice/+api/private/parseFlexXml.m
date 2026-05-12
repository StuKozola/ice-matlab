function tbl = parseFlexXml(xml)
%PARSEFLEXXML Convert /flexhistory XML to a table with a dynamic schema.
%   The response declares its own field types in <header>. Each <field>
%   may be a simple scalar (type=time|double|uint32|...) or a compound
%   type (e.g. RT_BarData) whose <element> children define sub-fields.
%
%   Output columns:
%     simple <field name="X" type="T"/>           -> column "X"  (typed)
%     compound <field name="X"><element name="Y"> -> column "X_Y" (per elem)
%
%   Time fields are converted to datetime (UTC) from epoch seconds.

arguments
    xml (1,1) string
end

xml = strip(xml);
if hasException(xml)
    raiseFromException(xml);
end
% /flexhistory error envelope: <flexhistory ... status="error code: -N, ..."/>
% with no <header> or <data> children. Surface as a typed exception.
statusErr = regexp(xml, '<flexhistory[^>]*\sstatus="(error[^"]*)"', "tokens", "once");
if ~isempty(statusErr)
    msg = string(statusErr{1});
    if startsWith(msg, "error code: -15")
        error("ice:api:NotEntitled", "ICE refused the flexhistory request: %s", msg);
    end
    error("ice:api:ResponseError", "flexhistory request failed: %s", msg);
end

tmp = string(tempname()) + ".xml";
fid = fopen(tmp, "w", "n", "UTF-8");
cleanup = onCleanup(@() safeDelete(tmp));
fwrite(fid, uint8(char(xml)));
fclose(fid);

s = readstruct(tmp, FileType="xml");

if ~isfield(s, "header") || ~isfield(s.header, "field")
    tbl = table();
    return
end

% Header: build a list of {colName, kind, elemNames(optional), type}.
headerFields = s.header.field;
if ~isstruct(headerFields); headerFields = struct(headerFields); end %#ok<NASGU>
nHead = numel(headerFields);
specs = cell(nHead, 1);
for k = 1:nHead
    hf = headerFields(k);
    name = string(hf.nameAttribute);
    type = string(hf.typeAttribute);
    if isfield(hf, "element") && ~isempty(hf.element) && ~all(ismissing(hf.element))
        elems = hf.element;
        if ~isstruct(elems); continue; end
        eNames = strings(numel(elems), 1);
        eTypes = strings(numel(elems), 1);
        for j = 1:numel(elems)
            eNames(j) = string(elems(j).nameAttribute);
            eTypes(j) = string(elems(j).typeAttribute);
        end
        specs{k} = struct("name", name, "type", type, ...
            "compound", true, "elemNames", eNames, "elemTypes", eTypes);
    else
        specs{k} = struct("name", name, "type", type, ...
            "compound", false, "elemNames", strings(0), "elemTypes", strings(0));
    end
end
specs = [specs{:}];

% Rows live under one or more <data id="..."> groups. For simplicity we
% concatenate rows from all data groups; if the caller wants per-symbol
% splits they can filter by the symbol column we add.
if ~isfield(s, "data")
    tbl = buildEmptyTable(specs);
    return
end
dataGroups = s.data;
if ~isstruct(dataGroups); dataGroups = struct(dataGroups); end %#ok<NASGU>

allRows = {};
allIds = {};
for g = 1:numel(dataGroups)
    grp = dataGroups(g);
    if ~isfield(grp, "row") || isempty(grp.row); continue; end
    rows = grp.row;
    if ~isstruct(rows); continue; end
    allRows{end+1} = rows;        %#ok<AGROW>
    if isfield(grp, "idAttribute")
        allIds{end+1} = repmat(string(grp.idAttribute), numel(rows), 1); %#ok<AGROW>
    else
        allIds{end+1} = repmat("", numel(rows), 1); %#ok<AGROW>
    end
end

if isempty(allRows)
    tbl = buildEmptyTable(specs);
    return
end

% Total row count across data groups.
nTotal = 0;
for k = 1:numel(allRows); nTotal = nTotal + numel(allRows{k}); end

% Pre-allocate columns per spec.
cols = struct();
for k = 1:numel(specs)
    sp = specs(k);
    if sp.compound
        for j = 1:numel(sp.elemNames)
            cols.(sp.name + "_" + sp.elemNames(j)) = ...
                allocateColumn(sp.elemTypes(j), nTotal);
        end
    else
        cols.(sp.name) = allocateColumn(sp.type, nTotal);
    end
end
symbolCol = strings(nTotal, 1);

% Fill row-by-row. For each row, walk its <field> children and copy by
% name (rather than position) so missing or reordered fields are tolerated.
idx = 0;
for g = 1:numel(allRows)
    grpRows = allRows{g};
    grpIds = allIds{g};
    for r = 1:numel(grpRows)
        idx = idx + 1;
        symbolCol(idx) = grpIds(r);
        row = grpRows(r);
        if ~isfield(row, "field"); continue; end
        rowFields = row.field;
        if ~isstruct(rowFields); continue; end
        for k = 1:numel(rowFields)
            fk = rowFields(k);
            fname = string(fk.nameAttribute);
            spec = findSpec(specs, fname);
            if isempty(spec); continue; end
            if spec.compound
                if isfield(fk, "element") && ~isempty(fk.element)
                    elems = fk.element;
                    if ~isstruct(elems); continue; end
                    for j = 1:numel(elems)
                        ej = elems(j);
                        ename = string(ej.nameAttribute);
                        colName = spec.name + "_" + ename;
                        if ~isfield(cols, colName); continue; end
                        cols.(colName) = setCell( ...
                            cols.(colName), idx, ej.Text, ...
                            findElemType(spec, ename));
                    end
                end
            else
                cols.(spec.name) = setCell( ...
                    cols.(spec.name), idx, fk.Text, spec.type);
            end
        end
    end
end

tbl = struct2table(cols);
tbl.symbol = symbolCol;
tbl = movevars(tbl, "symbol", "Before", 1);
end

function spec = findSpec(specs, name)
spec = [];
for k = 1:numel(specs)
    if specs(k).name == name
        spec = specs(k);
        return
    end
end
end

function t = findElemType(spec, ename)
t = "double";
for k = 1:numel(spec.elemNames)
    if spec.elemNames(k) == ename
        t = spec.elemTypes(k);
        return
    end
end
end

function col = allocateColumn(type, n)
switch lower(type)
    case "time"
        col = NaT(n, 1, TimeZone="UTC");
    case {"double", "float"}
        col = nan(n, 1);
    case {"uint8","uint16","uint32","uint64","int8","int16","int32","int64"}
        col = zeros(n, 1, lower(type));
    case "string"
        col = strings(n, 1);
    otherwise
        col = strings(n, 1);
end
end

function col = setCell(col, idx, rawVal, type)
% rawVal comes from readstruct: number for numeric types, string for text.
% time fields arrive as epoch-second integers in the docs example.
switch lower(type)
    case "time"
        v = double(rawVal);
        if ~isnan(v)
            col(idx) = datetime(v, ConvertFrom="posixtime", TimeZone="UTC");
        end
    case {"double", "float"}
        col(idx) = double(rawVal);
    case {"uint8","uint16","uint32","uint64","int8","int16","int32","int64"}
        cast = str2func(lower(type));
        col(idx) = cast(double(rawVal));
    case "string"
        col(idx) = string(rawVal);
    otherwise
        col(idx) = string(rawVal);
end
end

function tbl = buildEmptyTable(specs)
cols = struct();
for k = 1:numel(specs)
    sp = specs(k);
    if sp.compound
        for j = 1:numel(sp.elemNames)
            cols.(sp.name + "_" + sp.elemNames(j)) = ...
                allocateColumn(sp.elemTypes(j), 0);
        end
    else
        cols.(sp.name) = allocateColumn(sp.type, 0);
    end
end
cols.symbol = strings(0, 1);
tbl = struct2table(cols);
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
