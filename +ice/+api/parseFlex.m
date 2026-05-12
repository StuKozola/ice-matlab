function tbl = parseFlex(xml)
%PARSEFLEX Public wrapper for the private flexhistory parser.
%   Exposed so tests can verify the parser without going through Session.
tbl = parseFlexXml(xml);
end
