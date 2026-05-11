# ICE Market Data Ingestion — MATLAB Architecture Plan

**Date:** 2026-05-11
**Author:** Drafted for Stuart Kozola (Gradient Boosted Investments)
**Target environment:** MATLAB R2024b on Windows 11, working dir `D:\matlab`

---

## 1. What's in the ICE docs

### 1.1 API services

HTTPS GET/POST to `xml.dataservices.theice.com` (prod), UAT at `xml.ut.dataservices.theice.com`. Auth via `username`/`pwd` in query string.

| Service | Endpoint | Use |
|---|---|---|
| Quote | `/quote`, `/options` | Snapshot quotes; multiple symbols comma-delimited; ~75 fields incl. bid/ask/last/OHLC/IV; classic vs decimal vs display formatting; CUSIP/ISIN/SEDOL lookup; price delay indicator. Not a streaming substitute. |
| History (daily+) | `/xhist` | OHLCV+OI bars by `barintv`={daily, weekly, monthly, quarterly, yearly, 2d, 3w, 4m}; split-adjusted by default; continuous-futures via `%SYM 1!` + `contchart`; back-adjusted via cumulative `backadjt` pointer chained across requests; max 10y per request. **`startdate`/`enddate` must be UTC+0 as of 2025-12-17.** |
| History (intraday) | `/xtick` | i1/i2/i5 etc minute bars or tick-by-tick; `formt`/`outsession` for off-session data; bar-by-volume / bar-by-tick options; max 43,200 bars/request; split-**un**adjusted by default. |
| Flex history | `/flexhistory` | Non-OHLC fields (weather, mortgage, vessel, etc.); dynamic schema; epoch-second timestamps. |

**Limits across both APIs:** ≤20 concurrent outstanding requests, ≤20 req/s, advertise `Accept-Encoding: gzip`, scheduled bulk back-fills allowed only 01:00–07:00 ET (intraday) or 21/22:00–07:00 ET (daily+).

**Response shape:** XML.
- `xhist`/`xtick` root is `<xhist symbol="...">` with `<r date="..." time="...">` rows containing `<open><high><low><close><volume><openinterest>`.
- `/quote` root is `<quotes>` with `<quote status="ok|unknown" request="..." id="..." delay="...">`.
- Prices in `/quote` come in three formats — be aware of "classic" integer (e.g. `1050000` = $105.00) vs "decimal" vs "display".

### 1.2 FTP feeds

Hosts: `eod11|eod12|eod13.icedataservices.com` (FTP and SFTP both supported). User/pass per subscription.

| Product | Path | Schedule | Format |
|---|---|---|---|
| **EODD** | `/EODD/PUB<n>/EODD_PUB<n>_<srcID>-<entCode>_<yyyymmdd>.csv.gz` | within 15 min of exchange close; multiple PUBs/day | 33-column CSV, header lists `<TOKEN>` names — **must read header to map columns** because tokens are aliased per `ENUM.SRC.ID` (e.g. position 6 is `<TRADE.PRICE>` for equities but `<NAV.PRICE>` for funds). Datetimes UTC, `yyyymmdd hh:mm:ss`. |
| **FTPCSD** | `/FTPCSD_<srcID>_<yyyymmdd>.csv[.gz]` and (new layout) `/FTPCSD/PUB<n>/...` | per-region; US 03:30, EU 17:30, APAC 10:00, ME/AF 15:00 ET | ~70 columns: source ID, symbol, SEDOL, ISIN, MIC, Bloomberg ID, instrument type, currency, strike, expiry, contract size, etc. |
| **FTPSEDOL** | `/FTPSEDOL/PUB<n>/FTPSEDOL_PUB<n>_<yyyymmdd>.csv.bz2` | 5×/day (03:00, 09:30, 14:30, 18:00 ET + 01:00 prev) | 3 cols: `<ENUM.SRC.ID>,<SYMBOL.TICKER>,<SEDOL>`. **bzip2-compressed** (new compression standard ICE is migrating other products to). |
| **FTPCUSIP** | `/FTPCUSIP_<yyyymmdd>.csv` | ~03:30 ET | 4 cols: Exchange (hex ID), Symbol, CUSIP, ISIN. Limited license. |
| **FTPGICS** | `/FTPGICS_<yyyymmdd>.csv` | ~04:00 ET | 3 cols: Exchange, Symbol, GICS code. Limited license. |
| **FTPFD** | `/FTPFD_<yyyymmdd>.csv` | ~03:30 ET | ~60 fundamental fields per symbol (P/E, 52w high/low, dividends, FYE financials). |
| **FTPCA** | `/FTPCA_<exchID>_<yyyymmdd>.csv` | ~19:30 ET | Corporate actions: splits, dividends, name/symbol changes. |

**Symbology gotchas:**
- `ENUM.SRC.ID` is integer (e.g. `558` NYSE, `564` NASDAQ).
- Old "exchange ID" is octal-encoded (`0D`=13=NYSE).
- For commodities, `%C 1!` prefix forces commodity over equity on symbol collisions.
- Some text fields are HTML-escaped (`&amp;`, `&quot;` etc.).

---

## 2. Proposed MATLAB architecture

Single MATLAB toolbox/package, `+ice/` namespace, organized by feed type with shared infrastructure underneath. R2024b ships `webread`/`webwrite`/`weboptions` (HTTPS+gzip+keep-alive built in), `readtable`, `parquetwrite`, `xmlread`/`readstruct` — no MEX or external deps required.

### 2.1 Directory layout

```
D:\matlab\
├── +ice\
│   ├── +api\          % HTTP layer for Connect Enterprise XML services
│   │   ├── Session.m              % handle class: creds, host, throttler, gzip
│   │   ├── quote.m                % /quote and /options
│   │   ├── history.m              % /xhist daily+
│   │   ├── intradayHistory.m      % /xtick
│   │   ├── flexHistory.m          % /flexhistory
│   │   └── private/
│   │       ├── parseQuotesXml.m
│   │       ├── parseHistXml.m     % handles xhist/xtick (same shape)
│   │       ├── parseFlexXml.m
│   │       └── classicToDecimal.m % undoes "classic" integer scaling
│   ├── +ftp\          % SFTP layer for EOD products
│   │   ├── FtpSession.m           % handle class wraps MATLAB sftp; server rotation, atomic .part downloads, optional SSH-key auth
│   │   ├── listing.m              % filename discovery (incl. PUB<n> subdirs)
│   │   ├── download.m             % fetch+decompress (.gz / .bz2)
│   │   ├── readEodd.m
│   │   ├── readFtpcsd.m
│   │   ├── readFtpsedol.m
│   │   ├── readFtpcusip.m
│   │   ├── readFtpgics.m
│   │   ├── readFtpfd.m
│   │   ├── readFtpca.m
│   │   └── private/
│   │       ├── tokenMap.m         % column-token alias table (the 33-col EODD aliasing rules)
│   │       └── decodeOctalSrc.m   % "0D" <-> 13 lookup
│   ├── +sym\          % cross-reference: symbol <-> SEDOL/ISIN/CUSIP/Bloomberg
│   │   ├── SymbolCache.m          % builds from FTPCSD + FTPSEDOL + FTPCUSIP
│   │   └── lookup.m
│   ├── +jobs\         % non-interactive entry points for Windows Task Scheduler
│   │   ├── syncDailyEodd.m
│   │   ├── syncSymbolMaster.m
│   │   ├── backfillHistory.m
│   │   └── private/
│   │       └── runWithLock.m      % file-lock + JSON log wrapper
│   ├── +util\
│   │   ├── RateLimiter.m          % token bucket: ≤20 in-flight, ≤20 req/s
│   │   ├── Retry.m                % exponential back-off on 5xx / transient errors
│   │   ├── Cache.m                % parquet/MAT-backed cache rooted at ice.config.cacheRoot()
│   │   ├── log.m                  % structured logging (JSON per event + human summary)
│   │   ├── FileLock.m             % exclusive lock w/ stale-timeout (SMB-safe)
│   │   └── htmlUnescape.m         % FTP files have HTML-escaped text
│   └── +config\
│       ├── credentials.m          % resolves creds via MATLAB Vault (primary) → .env file (fallback) → env vars (last resort)
│       ├── setupVault.m           % one-time helper: prompts for FTP/API creds and writes them to Vault
│       └── cacheRoot.m            % resolves cache root: arg > ICE_CACHE_ROOT env > ice.config.local > default
├── examples\                      % plain-text Live Scripts (.m, matlab-live-script format)
│   ├── quote_snapshot.m
│   ├── history_daily.m
│   ├── history_intraday.m
│   ├── ftp_sync_eodd.m
│   └── build_symbol_master.m
├── scheduled\                     % Task Scheduler integration
│   ├── run_daily.bat              % invokes matlab -batch "ice.jobs.syncDailyEodd"
│   └── run_symbol_master.bat
├── tests\                         % matlab.unittest classes
│   ├── ApiSessionTest.m
│   ├── XmlParserTest.m            % fixtures = saved sample responses from user guides
│   ├── EoddReaderTest.m
│   ├── RateLimiterTest.m          % uses injected fake clock
│   └── fixtures\                  % canned XML/CSV used in lieu of UAT until creds arrive
└── data\                          % default cache root (overridable; .gitignored)
    ├── ftp_raw\                   % downloaded .csv.gz / .csv.bz2 (untouched)
    ├── parquet\                   % normalized parquet partitioned by srcid/date
    ├── logs\                      % YYYY-MM-DD.log
    └── .lock                      % file lock for scheduled jobs
```

### 2.2 Design choices and the tradeoffs behind them

1. **`webread` over Java HTTP**, with shared `weboptions(HeaderFields={'Accept-Encoding','gzip'}, ContentType='text', KeepAlive=true)`. Simpler, gzip-transparent, no class-loader headaches. Cost: less control over connection reuse — should be fine within the 20-req/s budget.

2. **Token-bucket `RateLimiter`** held by `Session` (singleton-ish per cred). Required because the docs explicitly threaten suspension for breach. All API calls go through it; `parfor`/`parfeval` consumers acquire tokens before issuing.

3. **Parallelism via Parallel Computing Toolbox.** Bulk back-fills use `parfeval` on a local pool; each worker takes a token from the shared `RateLimiter` before issuing its request, so concurrency stays under the 20-in-flight/20-per-second cap. Particularly useful for `backfillHistory(symbols, start, end)` over hundreds of symbols.

4. **XML parsing via `readstruct(text, FileType="xml")`** (R2024b feature) rather than `xmlread`+DOM. Gives a struct-of-arrays the rest of the pipeline can vectorize. Fall back to `xmlread` for `flexhistory` since its schema is dynamic. `xhist`/`xtick` share an identical row shape so one parser handles both.

5. **Price-format normalization at the boundary.** All `/quote` calls request `fields=...,-decimal` and all parsed prices stored as `double`. Never propagate "classic" integer-scaled prices upward — too easy to confuse downstream code with a number that's 10⁴ off.

6. **Configurable cache root.** `ice.config.cacheRoot()` resolves in this order: (a) argument passed to `Session`/`FtpSession` constructor, (b) `ICE_CACHE_ROOT` environment variable (best for scheduled jobs), (c) `ice.config.local.m` at toolbox root (gitignored, best for interactive dev), (d) default `D:\matlab\data\`. Sub-tree is identical under whatever root wins, so moving to a network share later is one env-var change. Two tiers inside it:
   - `ftp_raw\` — original `.gz`/`.bz2` files, never re-fetched if mtime matches. Manifest in MAT.
   - `parquet\` — normalized tables (`timetable` written via `parquetwrite`) partitioned by `srcid`/`date`. Cheaper to re-read than to re-request the API.

7. **EODD column aliasing.** The EODD spec says columns 6, 11, 12, 15, 16, 20, 21, 25, 26, 30, 31, 32 carry different tokens depending on source ID — and "It is recommended to read the EODD price file column headings to know what fields are available." So `readEodd` must trust the header row, not column position. The reader returns a `table` with normalized column names plus a `Properties.VariableDescriptions` mapping to the original CTF token. Saves us from a brittle per-srcid switch statement.

8. **bzip2 + gzip handling.** R2024b's built-in `gunzip` covers `.gz`. `.bz2` (FTPSEDOL and the migration target for everything else) isn't native — three options: (a) shell out to a static `bzip2.exe`, (b) use the JVM `org.apache.commons.compress` if present, (c) ship a tiny MEX or Python sidecar. Cleanest: detect at startup and prefer (a) → (b) → error with install instructions. **This is the single deployment dependency to call out to you.**

9. **FTP transport with opportunistic TLS and atomic downloads.** `FtpSession` wraps MATLAB's built-in `ftp` and (when explicitly requested) `sftp`. Production hosts `eod11/eod12/eod13.icedataservices.com` were verified at runtime to accept only **plain FTP on port 21** — SFTP/22 is reserved for the developer test host `idsftp.icedataservices.com`. The default is therefore `Protocol="ftp"` with `TlsMode="opportunistic"`, which upgrades to FTPS via `AUTH TLS` when the server supports it and falls back to cleartext when it doesn't. `TlsMode="strict"` refuses cleartext. Host rotation on connect failure. Each file downloads to `<name>.part` and is renamed on success so a killed transfer never leaves a corrupt cached file — important for the FTPCSD files that can hit 260 MB.

10. **Symbol master as a derived view, not a feed.** `+sym\SymbolCache` joins the latest FTPCSD + FTPSEDOL + FTPCUSIP into one wide `table` keyed by `(srcid, ticker)` with SEDOL/ISIN/CUSIP/Bloomberg columns. Rebuilt nightly from latest PUB. Everything downstream that needs to translate symbols hits this cache — never the raw files.

11. **Two entry-point layers on one core.** The `+api`, `+ftp`, `+sym` packages are usable directly from the command window or Live Scripts (interactive analysis). `+jobs` wraps the same building blocks for non-interactive batch use: takes a config struct, writes structured JSON logs to `<cacheRoot>\logs\YYYY-MM-DD.log`, exits with a nonzero MATLAB exit code on failure. `scheduled\run_daily.bat` invokes MATLAB via `-batch "ice.jobs.syncDailyEodd"` for Windows Task Scheduler — no persistent MATLAB process needed. A file lock at `<cacheRoot>\.lock` (with a stale-lock timeout, SMB-safe) prevents a slow run from colliding with the next trigger.

12. **MATLAB version of the Live Scripts.** Per `matlab-live-script` skill rules: `.m` plain text with `%[text]` rich text markers and the required `%[appendix]` footer. The user-facing entry points (`examples\*.m`) are written in this format so you can open them as Live Scripts.

13. **Credential storage — MATLAB Vault with `.env` fallback.** Primary store is MATLAB's **Vault** (`setSecret`/`getSecret`, R2024a+): platform-native secure store on Windows (DPAPI under the hood), survives MATLAB restarts, never appears in scripts or workspaces. A one-time `ice.config.setupVault()` prompts for `ICE_FTP_USER`, `ICE_FTP_PWD`, `ICE_API_USER`, `ICE_API_PWD` and writes them via `setSecret`. Runtime resolution in `ice.config.credentials()`:
   1. Try Vault first (`getSecret("ICE_FTP_USER")` etc.).
   2. Fall back to a `.env` file at toolbox root (gitignored; simple `KEY=value` lines parsed at session start) — useful for CI, containers, or copying to a new machine.
   3. Last-resort fall back to process env vars (covers the case where Task Scheduler sets them inline).
   
   The fallback chain means scheduled jobs work even if the Vault is locked to a different user account, and one-shot dev machines can use a `.env` without touching the Vault.

14. **Testing strategy.** Class-based `matlab.unittest` suites; XML parser tests load saved fixture responses (the literal samples from the user guides) so we never hit the network — these are the **primary integration check** until UAT credentials arrive. `RateLimiter` tested with a fake clock injected via constructor. Credential resolution tested with a temp directory and the Vault in a guard that restores prior values. CI later.

### 2.3 Phasing

| Phase | Scope | Verifies |
|---|---|---|
| 1 | `+util` (rate limiter, retry, logger, file lock, cache) + `+config` (credentials, cacheRoot) | Foundations testable in isolation |
| 2 | **FTP first (creds in hand):** `+ftp\FtpSession` (SFTP) + FTPCSD + FTPSEDOL readers; build `+sym\SymbolCache` | Real end-to-end against prod SFTP; decompression (.gz, .bz2); header-driven parsing; atomic downloads |
| 3 | EODD + FTPCA + FTPFD readers; first `+jobs\syncDailyEodd` + `scheduled\run_daily.bat` | Daily snapshot pipeline runs under Task Scheduler with file lock and JSON logs |
| 4 | `+api\Session`, `quote`, `history` (xhist/xtick) + XML parsers; **built against fixture XML from the user guides** until UAT creds arrive | Parsers, rate limiter, retry — all verified offline. Switch to live UAT (or prod, carefully) once creds land. |
| 5 | `flexhistory`, options chains, currency conversion; `+jobs\backfillHistory` with `parfeval` | Edge cases + parallel back-fill |
| 6 | Examples as Live Scripts, optional Database Toolbox sink, package the toolbox (`.mltbx`) | Distribution |

**Phase reordering rationale:** with FTP creds already in hand and no UAT yet, FTP work delivers live, verifiable value first; the XML APIs can be built and unit-tested against fixtures in parallel and switched on once UAT access arrives.

---

## 3. Decisions captured (2026-05-11)

1. **Credentials** — FTP and product credentials in hand. **No UAT access yet** for the XML APIs. → Phase 4 (APIs) built against fixture XML from the user guides; live API integration tests deferred until UAT lands. UAT access flagged as a parallel ask.
2. **MATLAB toolboxes** — all available. → Use Parallel Computing Toolbox (`parfeval`) for bulk back-fills; keep a Database Toolbox writer as an optional sink behind a flag; skip Datafeed Toolbox (no ICE adapter).
3. **FTP transport** — initially planned as SFTP, but runtime probing showed prod hosts `eod11/12/13` accept only plain FTP on port 21 (SFTP/22 is only on `idsftp.icedataservices.com`). Switched to MATLAB's built-in `ftp` with `TlsMode="opportunistic"` (auto-upgrade to FTPS via AUTH TLS when available); `Protocol="sftp"` flag retained for the developer host. Atomic `.part` → rename downloads for large FTPCSD files.
4. **Usage modes** — both scheduled and interactive. → `+jobs` package for non-interactive Task Scheduler runs (with file lock + JSON logs + nonzero exit on failure); `+api`/`+ftp`/`+sym` packages directly usable from command window or Live Scripts. `scheduled\run_daily.bat` invokes MATLAB via `-batch`.
5. **Cache root** — default to local `D:\matlab\data\`, but configurable. Resolution order: constructor arg > `ICE_CACHE_ROOT` env var > `ice.config.local.m` > default. Future move to a network share is one env-var change.
6. **Credentials** — MATLAB **Vault** (`setSecret`/`getSecret`) as the primary store; `.env` file at toolbox root as a backup. `ice.config.setupVault()` is the one-time onboarding helper; `ice.config.credentials()` is the runtime resolver (Vault → `.env` → process env vars).

---

## 5. Suggested starting point

**Phase 1 + Phase 2** — the smallest end-to-end slice that delivers live, verifiable value against the credentials you already have:
- `+util` foundations (rate limiter, retry, logger, file lock, cache).
- `+config\credentials` + `+config\setupVault` + `+config\cacheRoot`.
- One-time: run `ice.config.setupVault()` to write your FTP credentials into MATLAB Vault.
- `+ftp\FtpSession` (SFTP) + `download` (with `.gz`/`.bz2` handling).
- `readFtpcsd` + `readFtpsedol` returning normalized `table`s.
- A first `+sym\SymbolCache` built from those two.

That proves the Vault-backed credential resolver, SFTP transport, decompression, header-driven parsing, configurable cache, and symbol-master pipeline — all against real data — without needing UAT.
