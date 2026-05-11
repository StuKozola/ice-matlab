@echo off
REM ============================================================================
REM run_daily.bat — Daily ICE symbology sync (FTPCSD all srcIDs + FTPSEDOL PUB5)
REM
REM Designed for Windows Task Scheduler. Recommended schedule: daily, 06:00 ET,
REM after FTPSEDOL PUB5 has published (01:00 ET) and US FTPCSD has rebuilt
REM (~03:30 ET).
REM
REM Setup:
REM   - Configure FTP credentials once via ice.config.setupVault() OR via a
REM     .env file at D:\matlab\.env (see .env.example).
REM   - Optionally set ICE_CACHE_ROOT in the Task Scheduler "Edit Action -
REM     Environment Variables" UI (Windows 11) or via setx, e.g.
REM       setx ICE_CACHE_ROOT "E:\ice-cache"
REM   - Test interactively first:
REM       D:\matlab\scheduled\run_daily.bat
REM
REM Exit code: nonzero if the sync raised any error. Task Scheduler will
REM mark the task failed and you can wire up email/notification from there.
REM ============================================================================

setlocal

REM Pin the toolbox root so this script can live anywhere and still work.
set TOOLBOX_ROOT=%~dp0..

REM Use the user's installed MATLAB; override MATLAB_EXE if needed.
if "%MATLAB_EXE%"=="" set MATLAB_EXE=C:\MATLAB\R2024b\bin\matlab.exe

if not exist "%MATLAB_EXE%" (
    echo ERROR: MATLAB not found at "%MATLAB_EXE%". Set MATLAB_EXE env var.
    exit /b 2
)

"%MATLAB_EXE%" -batch ^
    "addpath('%TOOLBOX_ROOT%'); ice.jobs.syncDailySymbology();"

exit /b %ERRORLEVEL%
