%[text] # ICE Connect Enterprise API Smoke Test
%[text] Verifies the XML Quote and XML History endpoints against **production** (`xml.dataservices.theice.com`). Fires exactly **five** requests — kept deliberately small per the docs' guideline against polling.
%[text] Prerequisites:
%[text] - Run `ice.config.setupVault()` once and enter `ICE_API_USER` / `ICE_API_PWD` at the prompt, or place them in `.env` at the toolbox root.
%[text] - Your subscription must permit `/quote` and `/xhist` / `/xtick`. If it doesn't, the server returns `<xcpt n="…"/>` which is surfaced as `ice:api:ResponseError`.
%[text] Each request is rate-limited (default 8 in flight / 8 per second), well under ICE's 20-of-each ceiling. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the API session
session = ice.api.Session();
fprintf("API host: %s   user: %s\n", session.Host, session.Username);

%%
%[text] ## Call 1 — single-symbol snapshot (IBM)
q1 = ice.api.quote(session, "IBM", Fields=["recent","open","high","low","last","close"]);
disp(q1)

%%
%[text] ## Call 2 — multi-symbol snapshot (AAPL, MSFT, GOOG)
q2 = ice.api.quote(session, ["AAPL","MSFT","GOOG"], ...
    Fields=["recent","high","low","last","close"]);
disp(q2)

%%
%[text] ## Call 3 — daily bars (5 most recent for IBM)
%[text] Per the ICE API change of 2025-12-17, startdate/enddate are UTC+0. With NBars and no dates, the server returns the latest N bars.
h1 = ice.api.history(session, "IBM", NBars=5);
disp(h1)

%%
%[text] ## Call 4 — weekly bars for 2024 (IBM)
h2 = ice.api.history(session, "IBM", ...
    StartDate=datetime(2024,1,1), ...
    EndDate=datetime(2024,12,31), ...
    BarInterval="weekly");
fprintf("Weekly bars returned: %d\n", height(h2))
head(h2, 5)

%%
%[text] ## Call 5 — 20 one-minute intraday bars (IBM)
%[text] Returned in UTC; equity exchange holidays / off-hours return empty.
h3 = ice.api.intradayHistory(session, "IBM", Period="i1", NBars=20);
fprintf("Intraday bars returned: %d\n", height(h3))
head(h3, 5)
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
