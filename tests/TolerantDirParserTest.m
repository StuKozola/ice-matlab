classdef TolerantDirParserTest < matlab.unittest.TestCase

    methods (Test)
        function plainFile(tc)
            line = "-rw-r--r--  1 eoddadmin eoddadmin   12345 May 11 12:34 FTPCSD_558_20260511.csv.gz";
            d = ice.ftp.FtpSession.tolerantDirParser(line, "en_US");
            tc.verifyEqual(numel(d), 1);
            tc.verifyEqual(d(1).name, 'FTPCSD_558_20260511.csv.gz');
            tc.verifyEqual(d(1).bytes, 12345);
            tc.verifyFalse(d(1).isdir);
        end

        function directory(tc)
            line = "drwxr-xr-x  2 eoddadmin eoddadmin    4096 May 11 12:34 PUB1";
            d = ice.ftp.FtpSession.tolerantDirParser(line, "en_US");
            tc.verifyEqual(d.name, 'PUB1');
            tc.verifyTrue(d.isdir);
        end

        function symlinkTargetStripped(tc)
            line = "lrwxrwxrwx  1 eoddadmin eoddadmin      28 May 11 12:34 FTPCSD_558.csv -> FTPCSD_558_20260511.csv";
            d = ice.ftp.FtpSession.tolerantDirParser(line, "en_US");
            tc.verifyEqual(d.name, 'FTPCSD_558.csv');
        end

        function dotEntriesSkipped(tc)
            lines = [ ...
                "drwxr-xr-x  2 u g 4096 May 11 12:34 ."; ...
                "drwxr-xr-x  3 u g 4096 May 11 12:34 .."; ...
                "-rw-r--r--  1 u g 1024 May 11 12:34 real.csv"];
            d = ice.ftp.FtpSession.tolerantDirParser(lines, "en_US");
            tc.verifyEqual(numel(d), 1);
            tc.verifyEqual(d.name, 'real.csv');
        end

        function malformedLinesSkipped(tc)
            lines = [ ...
                "total 1234"; ...
                ""; ...
                "garbage line"; ...
                "-rw-r--r--  1 u g 100 May 11 12:34 ok.csv"];
            d = ice.ftp.FtpSession.tolerantDirParser(lines, "en_US");
            tc.verifyEqual(numel(d), 1);
            tc.verifyEqual(d.name, 'ok.csv');
        end

        function manyFiles(tc)
            % Stress test: hundreds of FTPCSD_<srcid>_<date>.csv.gz lines —
            % the exact scenario that breaks the built-in parser on the
            % live FTPCSD/ directory.
            srcids = 100 + (1:300);
            lines = strings(numel(srcids), 1);
            for k = 1:numel(srcids)
                lines(k) = sprintf("-rw-r--r--  1 u g 1024 May 11 12:34 FTPCSD_%d_20260511.csv.gz", srcids(k));
            end
            d = ice.ftp.FtpSession.tolerantDirParser(lines, "en_US");
            tc.verifyEqual(numel(d), 300);
            tc.verifyEqual(d(1).name, 'FTPCSD_101_20260511.csv.gz');
            tc.verifyEqual(d(end).name, 'FTPCSD_400_20260511.csv.gz');
        end
    end
end
