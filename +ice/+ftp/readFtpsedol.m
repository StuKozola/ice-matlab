function tbl = readFtpsedol(filePath)
%READFTPSEDOL Parse an FTPSEDOL file into a table.
%   tbl = ice.ftp.readFtpsedol("FTPSEDOL_PUB2_20240213.csv.bz2")
%
%   Handles .csv, .csv.gz, .csv.bz2. Returns a table with columns:
%       srcId (uint32) — ENUM.SRC.ID
%       ticker (string) — SYMBOL.TICKER
%       sedol (string) — 7-character SEDOL where available
%
%   The first row of every FTPSEDOL file is a CTF token header
%   ("<ENUM.SRC.ID>","<SYMBOL.TICKER>","<SEDOL>") which we use to verify
%   column order and then drop.

arguments
    filePath (1,1) string {mustBeFile}
end

plain = ice.ftp.decompress(filePath);

opts = detectImportOptions(plain, FileType="text", Delimiter=",");
opts.VariableNamingRule = "preserve";
opts.VariableTypes(:) = {'string'};
raw = readtable(plain, opts);

% Header check: token names live in the first row of values (the column
% headers in the file are themselves the tokens, and readtable already
% promoted them to VariableNames — so just verify them).
expected = ["<ENUM.SRC.ID>", "<SYMBOL.TICKER>", "<SEDOL>"];
actual = string(raw.Properties.VariableNames);
if numel(actual) < 3 || ~all(actual(1:3) == expected)
    error("ice:ftp:readFtpsedol:UnexpectedHeader", ...
        "Expected header %s but found %s", strjoin(expected, ","), strjoin(actual, ","));
end

tbl = table( ...
    uint32(str2double(raw.(actual(1)))), ...
    raw.(actual(2)), ...
    raw.(actual(3)), ...
    VariableNames=["srcId", "ticker", "sedol"]);
end
