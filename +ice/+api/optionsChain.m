function tbl = optionsChain(session, underlying, opts)
%OPTIONSCHAIN Stock or future option chain via /options.
%   tbl = ice.api.optionsChain(session, "AAPL")           % default: stock
%   tbl = ice.api.optionsChain(session, "ES U8", Type="future")
%
%   Returns one row per (strike, side) pair. The parent option's strike,
%   root, underlier, exchange, and dte attributes are repeated on both
%   the call row and the put row so the table is self-describing.
%
%   All /quote parameters are accepted via Fields/ClassicFormat (the
%   /options endpoint shares /quote's parameter set per the user guide).

arguments
    session ice.api.Session
    underlying (1,1) string
    opts.Type (1,1) string = "stock"         % "stock" or "future"
    opts.Fields (1,:) string = string.empty
    opts.ClassicFormat (1,1) logical = false
end

params = struct();
params.symbols = underlying;
params.type = opts.Type;

fieldList = string(opts.Fields);
if ~opts.ClassicFormat
    fieldList(end+1) = "-decimal";
end
if ~isempty(fieldList)
    params.fields = strjoin(fieldList, ",");
end

xml = session.request("options", params);
tbl = parseOptionsXml(xml);
end
