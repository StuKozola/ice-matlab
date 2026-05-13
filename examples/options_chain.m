%[text] # ICE Options Chain — AAPL
%[text] Pulls the full stock-options chain for a single underlying via `/options` and explores it in long format (one row per `(strike, side)`). Each row carries the chain-level metadata (strike, underlier, root, exchange) plus the per-side quote fields (bid, ask, last, openint, delta, impvol, ...).
%[text] Prerequisites:
%[text] - `ice.config.setupVault()` populated with `ICE_API_USER` / `ICE_API_PWD`, **or** the same in `.env`.
%[text] - Subscription includes stock-options data on `/options`. \
addpath(fileparts(fileparts(mfilename("fullpath"))));
%%
%[text] ## Open the API session
session = ice.api.Session();

%%
%[text] ## Fetch the full AAPL chain
%[text] Returns one row per (strike, side). The full chain is on the order of a thousand options on a typical day, so expect a few seconds of parse time on a 4–5 MB XML response.
chain = ice.api.optionsChain(session, "AAPL", Type="stock");
fprintf("Rows: %d, Cols: %d\n", height(chain), width(chain))
fprintf("Distinct strikes: %d\n", numel(unique(chain.strike)))
fprintf("Sides: %s\n", strjoin(unique(chain.side), ", "))

%%
%[text] ## Note on strike units
%[text] `chain.strike` is the raw value as ICE delivers it. ICE also sends a per-side `strikeexp` exponent (typically `-2`), which is the implicit scale **for prices on that contract**, not necessarily for the strike itself — the relationship between `strike` and the underlying's quoted price differs by asset class and isn't worth automating in a general example. Spot-check it on a few liquid strikes before any production analysis. The rest of this script just uses `strike` as the join key between calls and puts and lets you eyeball the absolute level.

%%
%[text] ## Split into call and put sides
%[text] Many analyses want puts and calls side-by-side at each strike. The long-format table is easy to pivot.
callRows = chain(chain.side == "call", :);
putRows  = chain(chain.side == "put",  :);
fprintf("calls: %d   puts: %d\n", height(callRows), height(putRows))

%%
%[text] ## Highest-open-interest call
%[text] Spot a contract worth attention without needing the spot price.
[~, hiOI] = max(callRows.openint);
disp(callRows(hiOI, ["underlier","strike","side","bid","ask","last","openint","delta","impvol"]))

%%
%[text] ## Implied-volatility smile (call side, today)
%[text] Quick smile plot across all strikes for the call side. NaNs and zeros are common — illiquid strikes often have no IV reported.
mask = callRows.impvol > 0 & ~isnan(callRows.impvol);
figure("Visible","on");
plot(callRows.strike(mask), 100*callRows.impvol(mask), ".-");
xlabel("Strike (raw)"); ylabel("Implied vol (%)");
title("AAPL call-side IV smile");
grid on;

%%
%[text] ## Open interest by strike
%[text] Sums call + put OI per strike — useful for spotting gamma-exposure clusters.
oiByStrike = groupsummary(chain, "strike", "sum", "openint");
oiByStrike = sortrows(oiByStrike, "strike");
figure("Visible","on");
bar(oiByStrike.strike, oiByStrike.sum_openint);
xlabel("Strike (raw)"); ylabel("Open interest (call + put)");
title("AAPL OI distribution");
grid on;
%[text]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
