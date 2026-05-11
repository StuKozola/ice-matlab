function tbl = parseQuotes(xml)
%PARSEQUOTES Public wrapper for the private quote parser.
%   Exposed so tests can verify the parser without going through Session.
tbl = parseQuotesXml(xml);
end
