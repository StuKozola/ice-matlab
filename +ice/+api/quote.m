function tbl = quote(session, symbols, opts)
%QUOTE Snapshot quote for one or more symbols.
%   tbl = ice.api.quote(session, ["AAPL", "MSFT"])
%   tbl = ice.api.quote(session, "ES", Type="future", Fields=["recent","high","low"])
%
%   Defaults to decimal price formatting (prices come back as actual
%   dollar values, not the legacy integer-scaled "classic" format).
%   Set ClassicFormat=true if you specifically need the integer form.

arguments
    session ice.api.Session
    symbols (1,:) string
    opts.Fields (1,:) string = string.empty
    opts.Type   (1,1) string = ""
    opts.ClassicFormat (1,1) logical = false
    opts.DispFullName  (1,1) logical = false
    opts.Convert   (1,:) string = string.empty
    opts.ConvertTo (1,1) string = ""
end

params = struct();
params.symbols = strjoin(symbols, ",");

% Fields parameter: list of fields plus formatting hint (-decimal / -classic).
fieldList = string(opts.Fields);
if ~opts.ClassicFormat
    fieldList(end+1) = "-decimal";
end
if ~isempty(fieldList)
    params.fields = strjoin(fieldList, ",");
end
if strlength(opts.Type) > 0
    params.type = opts.Type;
end
if opts.DispFullName
    params.dispfullname = "y";
end
if ~isempty(opts.Convert)
    params.convert = strjoin(opts.Convert, ",");
end
if strlength(opts.ConvertTo) > 0
    params.convertto = opts.ConvertTo;
end

xml = session.request("quote", params);
tbl = parseQuotesXml(xml);
end
