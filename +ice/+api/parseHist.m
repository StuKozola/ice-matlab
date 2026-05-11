function tt = parseHist(xml)
%PARSEHIST Public wrapper for the private xhist/xtick parser.
%   Exposed so tests can verify the parser without going through Session.
tt = parseHistXml(xml);
end
