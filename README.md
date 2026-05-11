# ice-matlab

MATLAB toolbox for ingesting [ICE Data Services](https://www.theice.com/market-data) market data:

- **Connect Enterprise API (XML)** — `/quote`, `/options`, `/xhist`, `/xtick`, `/flexhistory`
- **FTP feeds** — EODD, FTPCSD, FTPSEDOL, FTPCUSIP, FTPGICS, FTPFD, FTPCA

Target environment: MATLAB R2024b on Windows. FTP transport via MATLAB's built-in `ftp` object with opportunistic TLS (production hosts `eod11/12/13.icedataservices.com` accept only port 21; SFTP is reserved for `idsftp.icedataservices.com`, the developer test site). Credentials stored in MATLAB Vault (with `.env` fallback).

## Status

Phases 1–4 implemented; 72 unit tests passing.

- **Phase 1** — foundations: `+util` (rate limiter, retry, cache, file lock, structured log) and `+config` (Vault- and `.env`-backed credentials).
- **Phase 2** — FTP transport + FTPCSD/FTPSEDOL readers + `SymbolCache`.
- **Phase 3** — `ice.jobs.syncDailySymbology` batch job and `scheduled/run_daily.bat` Task Scheduler wrapper.
- **Phase 4** — XML Quote / History API client (`ice.api.Session`, `ice.api.quote`, `ice.api.history`, `ice.api.intradayHistory`) talking to production.

See [`ICE_MATLAB_Architecture_Plan.md`](ICE_MATLAB_Architecture_Plan.md) for the full design.

## Layout

```
+ice/           % MATLAB toolbox (planned)
  +api/         % HTTPS XML services
  +ftp/         % FTP/SFTP file readers
  +sym/         % symbol cross-reference
  +jobs/        % non-interactive batch entry points
  +util/        % rate limiter, retry, cache, file lock
  +config/      % credentials (Vault), cache root
examples/       % plain-text Live Scripts
scheduled/      % Windows Task Scheduler .bat wrappers
tests/          % matlab.unittest classes + fixtures
extract_pdfs.py % helper for reading ICE developer PDFs locally
```

## Note on ICE documentation

ICE developer guides are proprietary and **not committed** to this repository. They are expected to live locally in `ice_developer_docs/` (gitignored).
