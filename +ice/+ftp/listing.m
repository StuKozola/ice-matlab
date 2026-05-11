function names = listing(session, product, opts)
%LISTING Enumerate available files for an ICE FTP product.
%   names = ice.ftp.listing(session, "FTPSEDOL", Pub=2)
%   names = ice.ftp.listing(session, "FTPCSD")
%
%   Maps product names to their directory layout per the ICE docs and
%   returns the filenames found there, sorted descending by name so the
%   most recent file is first.

arguments
    session ice.ftp.FtpSession
    product (1,1) string
    opts.Pub (1,1) double = NaN          % 1..5 for FTPSEDOL/EODD
    opts.Year (1,1) double = NaN
end

product = upper(product);
switch product
    case "FTPSEDOL"
        if isnan(opts.Pub)
            remote = "FTPSEDOL";
        else
            remote = sprintf("FTPSEDOL/PUB%d", opts.Pub);
        end
    case "FTPCSD"
        % FTPCSD has both legacy root layout and new PUB layout; check root.
        remote = ".";
    case "EODD"
        pub = opts.Pub;
        if isnan(pub); pub = 1; end
        remote = sprintf("EODD/PUB%d", pub);
    case {"FTPCUSIP", "FTPGICS", "FTPFD", "FTPCA"}
        remote = ".";
    otherwise
        error("ice:ftp:listing:UnknownProduct", ...
            "Unknown product '%s'. Supported: FTPSEDOL, FTPCSD, EODD, FTPCUSIP, FTPGICS, FTPFD, FTPCA.", ...
            product);
end

names = session.list(remote);
prefix = filterPrefix(product);
if strlength(prefix) > 0
    names = names(startsWith(names, prefix));
end
names = sort(names, "descend");
end

function p = filterPrefix(product)
switch product
    case "FTPSEDOL", p = "FTPSEDOL";
    case "FTPCSD",   p = "FTPCSD_";
    case "EODD",     p = "EODD_";
    case "FTPCUSIP", p = "FTPCUSIP";
    case "FTPGICS",  p = "FTPGICS";
    case "FTPFD",    p = "FTPFD";
    case "FTPCA",    p = "FTPCA_";
    otherwise,       p = "";
end
end
