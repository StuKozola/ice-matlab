function tbl = parseOptions(xml)
%PARSEOPTIONS Public wrapper for the private /options parser.
%   Exposed so tests can verify the parser without going through Session.
tbl = parseOptionsXml(xml);
end
