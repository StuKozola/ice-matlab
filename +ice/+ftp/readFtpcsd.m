function tbl = readFtpcsd(filePath)
%READFTPCSD Parse a Consolidated Feed Symbol Directory file into a table.
%   tbl = ice.ftp.readFtpcsd("FTPCSD_558_20180812.csv.gz")
%
%   Handles .csv, .csv.gz, .csv.bz2. Returns a wide table whose column
%   names come from the file's CTF token header (e.g. <ENUM.SRC.ID>,
%   <SYMBOL.TICKER>, <SEDOL>, <ISIN>, <INSTR_NAME2>, ...).
%
%   Token names are normalized to MATLAB-friendly identifiers by stripping
%   the angle brackets and replacing dots and dashes with underscores. The
%   original token is preserved as the column's VariableDescription so
%   downstream code can map back when needed.
%
%   A handful of commonly-typed columns are coerced to richer types:
%       srcId            -> uint32       (was ENUM_SRC_ID)
%       strikePrice      -> double       (STRIKE_PRICE)
%       expirationDate   -> datetime     (EXPIRATION_DATE, yyyymmdd)
%       maturityDate     -> datetime     (MATURITY_DATE, yyyymmdd)
%       contractSize     -> double
%       tickSize         -> double
%   All other columns remain string for safety; callers cast as needed.

arguments
    filePath (1,1) string {mustBeFile}
end

plain = ice.ftp.decompress(filePath);

opts = detectImportOptions(plain, FileType="text", Delimiter=",");
opts.VariableNamingRule = "preserve";
opts.VariableTypes(:) = {'string'};
% Some FTPCSD rows have fewer columns than the header when trailing fields
% are blank — readtable defaults handle this by padding with missing.
opts.ExtraColumnsRule = "ignore";
opts.EmptyLineRule = "skip";
raw = readtable(plain, opts);

origTokens = string(raw.Properties.VariableNames);
niceNames = arrayfun(@normalizeTokenName, origTokens);

% Resolve duplicate normalized names by suffixing _2, _3, ...
[uniqueNames, idx] = uniqueResolveDupes(niceNames);
raw.Properties.VariableNames = cellstr(uniqueNames);
raw.Properties.VariableDescriptions = cellstr(origTokens(idx));

tbl = coerceCommonColumns(raw);
end

% --------------------------------------------------------------------------

function out = normalizeTokenName(token)
% "<ENUM.SRC.ID>" -> "ENUM_SRC_ID"
out = token;
out = replace(out, "<", "");
out = replace(out, ">", "");
out = replace(out, ".", "_");
out = replace(out, "-", "_");
out = replace(out, " ", "_");
out = string(matlab.lang.makeValidName(out, ReplacementStyle="underscore"));
end

function [resolved, originalIdx] = uniqueResolveDupes(names)
resolved = names;
originalIdx = (1:numel(names)).';
seen = containers.Map('KeyType','char','ValueType','int32');
for k = 1:numel(names)
    key = char(names(k));
    if isKey(seen, key)
        seen(key) = seen(key) + 1;
        resolved(k) = string(key) + "_" + string(seen(key));
    else
        seen(key) = 1;
    end
end
end

function tbl = coerceCommonColumns(tbl)
% Map likely column names to coercions. Keys are exact post-normalization
% column names; values are conversion functions returning the new column.
rules = { ...
    "ENUM_SRC_ID",      @(c) uint32(str2double(c)); ...
    "STRIKE_PRICE",     @(c) toNumeric(c); ...
    "EXPIRATION_DATE",  @(c) toDateYYYYMMDD(c); ...
    "MATURITY_DATE",    @(c) toDateYYYYMMDD(c); ...
    "CONTRACT_SIZE",    @(c) toNumeric(c); ...
    "TICK_SIZE",        @(c) toNumeric(c); ...
    "MULTIPLIER",       @(c) toNumeric(c); ...
    "OUTSTANDING_AMT",  @(c) toNumeric(c); ...
    "COUPON_RATE",      @(c) toNumeric(c); ...
    "OPEN_INT",         @(c) toNumeric(c)};

for k = 1:size(rules, 1)
    name = rules{k, 1};
    if ismember(name, string(tbl.Properties.VariableNames))
        try
            tbl.(name) = rules{k, 2}(tbl.(name));
        catch err
            warning("ice:ftp:readFtpcsd:CoercionFailed", ...
                "Could not coerce %s: %s", name, err.message);
        end
    end
end

% Convert low-cardinality string columns to categorical. Drastically cuts
% memory before vertcat across hundreds of FTPCSD files: a categorical
% holds one shared lookup table plus an integer index per row, vs a string
% which holds the full text per row.
catColumns = ["CURRENCY_STRING", "MIC_CODE", "OPERATING_MIC", ...
              "MIC_CODE_REF_MKT", "INSTR_TYPE", "INSTR_LOCAL_TYPE", ...
              "INSTR_LOCAL_TYPE2", "INSTR_LOCAL_TYPE3", ...
              "FUND_RECORD_STATUS", "FUND_LOCAL_IND_SECTOR", ...
              "PUT_CALL_IND", "EXER_STYLE", "ADJUSTMENT_IND", ...
              "ENUM_STRATEGY_TYPE", "STRATEGY_TYPE", ...
              "ENUM_CONTRACT_UNITS", "CONTRACT_UNITS", ...
              "OPTION_EXPIRY_TYPE", "ENUM_EXPIRATION_CYCLE", ...
              "INSTR_LIQUIDITY_STATUS", "QUOTATION_BASIS_MARKER", ...
              "ACCRUED_INTEREST_STYLE", "REFERENCE_INSTRUMENT_INDICATOR", ...
              "MKT_SUB_ABRV", "ENUM_MKT_SUB_ID", "MKT_SEGMENT_STRING", ...
              "CFI_CODE", "TRADING_GROUP_CODE", "TRADING_GROUP_CODE_2"];
present = intersect(catColumns, string(tbl.Properties.VariableNames));
for k = 1:numel(present)
    name = present(k);
    try
        tbl.(name) = categorical(tbl.(name));
    catch
        % If a value collides with a reserved categorical name or similar,
        % leave it as string rather than failing the whole read.
    end
end

% Friendlier final names for the most-used coerced columns:
tbl = renameIfPresent(tbl, "ENUM_SRC_ID",     "srcId");
tbl = renameIfPresent(tbl, "SYMBOL_TICKER",   "ticker");
tbl = renameIfPresent(tbl, "SEDOL",           "sedol");
tbl = renameIfPresent(tbl, "ISIN",            "isin");
tbl = renameIfPresent(tbl, "INSTR_NAME2",     "name");
tbl = renameIfPresent(tbl, "MIC_CODE",        "mic");
tbl = renameIfPresent(tbl, "CURRENCY_STRING", "currency");
tbl = renameIfPresent(tbl, "STRIKE_PRICE",    "strikePrice");
tbl = renameIfPresent(tbl, "EXPIRATION_DATE", "expirationDate");
tbl = renameIfPresent(tbl, "MATURITY_DATE",   "maturityDate");
tbl = renameIfPresent(tbl, "CONTRACT_SIZE",   "contractSize");
tbl = renameIfPresent(tbl, "TICK_SIZE",       "tickSize");
end

function tbl = renameIfPresent(tbl, oldName, newName)
if ismember(oldName, string(tbl.Properties.VariableNames))
    tbl = renamevars(tbl, oldName, newName);
end
end

function v = toNumeric(c)
v = str2double(c);
v(ismissing(c) | strlength(c) == 0) = NaN;
end

function v = toDateYYYYMMDD(c)
v = NaT(size(c));
mask = strlength(c) == 8;
if any(mask)
    v(mask) = datetime(char(c(mask)), InputFormat="yyyyMMdd");
end
end
