# ice-matlab

MATLAB toolbox for ingesting [ICE Data Services](https://www.theice.com/market-data) market data:

- **Connect Enterprise API (XML)** — `/quote`, `/options`, `/xhist`, `/xtick`, `/flexhistory`
- **FTP feeds** — EODD, FTPCSD, FTPSEDOL, FTPCUSIP, FTPGICS, FTPFD, FTPCA

Target environment: MATLAB R2024b on Windows. FTP transport via MATLAB's built-in `ftp` object with opportunistic TLS (production hosts `eod11/12/13.icedataservices.com` accept only port 21; SFTP is reserved for `idsftp.icedataservices.com`, the developer test site). Credentials stored in MATLAB Vault (with `.env` fallback).

## Status

Pre-implementation. See [`ICE_MATLAB_Architecture_Plan.md`](ICE_MATLAB_Architecture_Plan.md) for the full design and phasing.

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
