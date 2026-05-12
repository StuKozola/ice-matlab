classdef HarmonizePartsTest < matlab.unittest.TestCase
    %HarmonizePartsTest Exercises SymbolCache.build with parts that have
    %   - differing column sets
    %   - differing categorical level sets per column
    %   This is the actual fix-target for the 311-file OOM.

    properties
        TempRoot string
        OrigEnv  string
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = string(tempname()); mkdir(tc.TempRoot);
            tc.OrigEnv = string(getenv("ICE_CACHE_ROOT"));
            setenv("ICE_CACHE_ROOT", char(tc.TempRoot));
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            setenv("ICE_CACHE_ROOT", char(tc.OrigEnv));
            if isfolder(tc.TempRoot)
                rmdir(tc.TempRoot, "s");
            end
        end
    end

    methods (Test)
        function partsWithDifferentColumnsConcatenate(tc)
            % File A has columns [a, b]; file B has columns [a, c].
            csdA = fullfile(tc.TempRoot, "FTPCSD_A.csv");
            writeCsd(csdA, ...
                ["<ENUM.SRC.ID>","<SYMBOL.TICKER>","<INSTR_NAME2>","<CURRENCY.STRING>","<INSTR.LOCAL_TYPE>"], ...
                {["558" "AAPL" "APPLE INC" "USD" "CS"]; ...
                 ["558" "MSFT" "MICROSOFT"  "USD" "CS"]});
            csdB = fullfile(tc.TempRoot, "FTPCSD_B.csv");
            writeCsd(csdB, ...
                ["<ENUM.SRC.ID>","<SYMBOL.TICKER>","<INSTR_NAME2>","<MIC.CODE>","<TICK.SIZE>"], ...
                {["193" "ACSEL" "ACSELSAN" "XIST" "0.01"]});

            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=[string(csdA) string(csdB)], ShowProgress=false);

            t = s.table();
            tc.verifyEqual(height(t), 3);

            % Columns from both parts must be present.
            vars = string(t.Properties.VariableNames);
            for expected = ["srcId","ticker","name","currency","mic","tickSize"]
                tc.verifyTrue(any(vars == expected), "Missing column: " + expected);
            end

            % Row from part A has missing mic; row from part B has missing currency.
            apple = t(t.ticker == "AAPL", :);
            tc.verifyTrue(ismissing(apple.mic));
            acsel = t(t.ticker == "ACSEL", :);
            tc.verifyTrue(ismissing(acsel.currency));
        end

        function categoricalLevelsAreUnioned(tc)
            csdA = fullfile(tc.TempRoot, "FTPCSD_A.csv");
            writeCsd(csdA, ...
                ["<ENUM.SRC.ID>","<SYMBOL.TICKER>","<INSTR_NAME2>","<CURRENCY.STRING>"], ...
                {["558" "AAPL" "APPLE INC" "USD"]; ["558" "MSFT" "MICROSOFT" "USD"]});
            csdB = fullfile(tc.TempRoot, "FTPCSD_B.csv");
            writeCsd(csdB, ...
                ["<ENUM.SRC.ID>","<SYMBOL.TICKER>","<INSTR_NAME2>","<CURRENCY.STRING>"], ...
                {["193" "ACSEL" "ACSELSAN" "TRY"]});

            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=[string(csdA) string(csdB)], ShowProgress=false);

            t = s.table();
            tc.verifyEqual(height(t), 3);
            tc.verifyClass(t.currency, "categorical");
            cats = string(categories(t.currency));
            tc.verifyTrue(any(cats == "USD"));
            tc.verifyTrue(any(cats == "TRY"));
        end

        function categoricalColumnsReduceMemory(tc)
            % Smoke check: rebuilding two identical large parts uses memory
            % proportional to row count, not row*chars. We just confirm the
            % build completes (the real OOM lives on the 311-file path).
            csd = fullfile(tc.TempRoot, "FTPCSD.csv");
            cols = ["<ENUM.SRC.ID>","<SYMBOL.TICKER>","<INSTR_NAME2>", ...
                    "<CURRENCY.STRING>","<MIC.CODE>","<INSTR.LOCAL_TYPE>"];
            n = 5000;
            rows = cell(n, 1);
            for k = 1:n
                rows{k} = ["558", "T" + string(k), "name", "USD", "XNYS", "CS"];
            end
            writeCsd(csd, cols, rows);

            s = ice.sym.SymbolCache();
            s.build(FtpcsdFiles=[string(csd) string(csd)], ShowProgress=false);
            t = s.table();
            tc.verifyEqual(height(t), 2 * n);
            tc.verifyClass(t.currency, "categorical");
        end
    end
end

function writeCsd(path, header, rows)
quoted = """" + header + """";
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", strjoin(quoted, ","));
for k = 1:numel(rows)
    quotedRow = """" + rows{k} + """";
    fprintf(fid, "%s\n", strjoin(quotedRow, ","));
end
end
