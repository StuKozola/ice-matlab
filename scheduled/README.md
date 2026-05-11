# Scheduled jobs

This folder holds Windows Task Scheduler wrappers for the non-interactive
`+ice/+jobs/` entry points. Each `.bat` file is a thin launcher around
`matlab -batch "ice.jobs.<name>()"`. The job itself does all the real work
— acquire file lock, fetch, parse, log, set exit code.

## Files

- `run_daily.bat` — launches `ice.jobs.syncDailySymbology`. Recommended
  schedule: **once daily, 06:00 Eastern**, after FTPSEDOL PUB5 has
  published (~01:00 ET) and US FTPCSD has rebuilt (~03:30 ET).

## One-time setup

### 1. Verify the script runs interactively first

Open a normal PowerShell or `cmd` window (no admin privileges needed) and
run the `.bat` file directly:

```cmd
D:\matlab\scheduled\run_daily.bat
```

You should see:

- The cleartext-FTP warning (expected).
- A series of structured log lines: `sync_start`, `sync_enum_csd`,
  `sync_enum_sedol`, `sync_plan`, optional download events, `sync_build_*`,
  `sync_done`.
- A `summary` struct (or no output if you pipe through `-batch`).

If this fails, **fix it before scheduling.** A scheduled task running with
broken credentials or a missing dependency is much harder to debug.

The first interactive run will download the full daily symbology
(~3 GB compressed, a few minutes on a decent connection). Subsequent runs
are nearly instant because the cache layer skips files already on disk.

### 2. Open Task Scheduler

Start menu → search "Task Scheduler" → enter.

Right pane → **Create Task...** (NOT "Create Basic Task" — we need more
control than the basic wizard provides).

### 3. General tab

- **Name:** `ICE symbology daily sync`
- **Description:** `Runs ice.jobs.syncDailySymbology() each morning to refresh FTPCSD + FTPSEDOL and rebuild the symbol master.`
- **Security options:**
  - "Run whether user is logged on or not" — pick this so the job runs at
    06:00 even if you're not signed in.
  - "Run with highest privileges" — **not required** unless your cache root
    is in a location only Administrators can write to. Leave unchecked
    otherwise.
- **Configure for:** Windows 11.

When you save, Task Scheduler will prompt for your Windows password. This
is needed to start the task while you're logged out and to access the
**MATLAB Vault** entries — the Vault is scoped to your Windows account, so
the task **must** run as your user (not SYSTEM, not a service account).

### 4. Triggers tab

**New...** → **Begin the task: On a schedule** → **Daily** → start at
`06:00:00`, recur every `1` day. Leave the rest at defaults.

Optional: tick "Stop task if it runs longer than" and set 1 hour. The job
should finish in well under that; this is just a safety net against a
hung MATLAB.

### 5. Actions tab

**New...** → **Action: Start a program**

- **Program/script:** `D:\matlab\scheduled\run_daily.bat`
- **Add arguments:** *(leave empty)*
- **Start in:** `D:\matlab\scheduled`

Click **OK**.

### 6. Conditions tab

- Uncheck "Start the task only if the computer is on AC power" if this is
  a laptop that you want to sync on battery.
- Leave "Wake the computer to run this task" checked if your machine
  sleeps overnight.

### 7. Settings tab

- "Allow task to be run on demand" — checked.
- "Run task as soon as possible after a scheduled start is missed" —
  checked. (Catches the case where the machine was off at 06:00.)
- "If the task fails, restart every" — checked, every `15 minutes`, up to
  `3 times`. Avoids spurious failures from transient network blips.
- "If the running task does not end when requested, force it to stop" —
  checked.

Click **OK**. You'll be prompted for your Windows password to save the
"run whether logged on or not" setting.

## Verifying it works

### Trigger an immediate run

In Task Scheduler, find the task in the library, right-click → **Run**.

The task should show **Running** for the duration of the sync. Once it
completes, **Last Run Result** should read `0x0` (success). Anything
non-zero means the job raised an error.

### Check the logs

The job writes a structured JSON log line per event to:

```
<cacheRoot>\logs\YYYY-MM-DD.log
```

(Default cache root: `D:\matlab\data\logs\`. Override with `ICE_CACHE_ROOT`.)

Each line is a complete JSON record. Look for the trailing `sync_done`
event with the day's summary:

```json
{"ts":"2026-05-12T11:01:17.234Z","level":"info","event":"sync_done",
 "payload":{"csdSources":311,"ftpsedolFile":"...","downloaded":311,
 "alreadyCached":0,"masterRows":12345678,"elapsedSeconds":423.7}}
```

If you see `sync_start` but no `sync_done`, the job died midway —
look for the nearest `level":"error"` or `api_request_failed` /
`ftp_connect_fail` event for the cause.

### Task Scheduler's own history

In Task Scheduler, select the task → bottom pane → **History** tab. Each
trigger fires an event. The `Last Run Result` column shows the exit code;
any non-zero value indicates failure (Task Scheduler shows it as
`0x80004005` etc., MATLAB's nonzero exit code is what we set).

## Troubleshooting

### "Last Run Result: 0x1" or any non-zero code

The job raised an error. Open today's log file under
`<cacheRoot>\logs\` and search for the latest `level":"error"` or
`level":"warn"` event. The most likely failure modes:

- **`ftp_connect_fail`** — FTP credentials wrong or all three ICE hosts
  unreachable.
- **No log file** at all — MATLAB couldn't start. Check the MATLAB
  install path matches `MATLAB_EXE` in `run_daily.bat`, and run the .bat
  interactively to see the real error.
- **`ice:util:FileLock:Busy`** — a previous run is still going. Either
  wait for it to finish or, if it's clearly stuck, delete
  `<cacheRoot>\.lock` manually.

### "Could not start the task" from Task Scheduler

Usually a credential issue with the **scheduled-task** account (your
Windows password), not the ICE credentials. Re-edit the task and confirm
your password when prompted.

### Job runs but credentials aren't found

The Vault is scoped to one Windows user account. If the task is set to
run under a different account than the one you used to populate the
Vault (`ice.config.setupVault()`), it won't find `ICE_FTP_USER` etc.

Two fixes:

- **Easiest:** make sure the task's "When running the task, use the
  following user account" matches the user that ran `setupVault()`.
- **Alternative:** populate the `.env` file at `D:\matlab\.env` with the
  same credentials. `ice.config.credentials` falls back to `.env` when
  the Vault lookup fails, so this works regardless of which account
  runs the task.

### Skipping a run

If you need to skip a day (e.g. you know ICE is doing maintenance),
right-click the task → **Disable**. Re-enable when ready. Or, in Task
Scheduler's settings, the "Run task as soon as possible after a
scheduled start is missed" option will catch up automatically once you
re-enable it.

### Watching it run live

Open the log file in a tool that follows tails, e.g.:

```powershell
Get-Content D:\matlab\data\logs\$((Get-Date).ToString('yyyy-MM-dd')).log -Wait
```

Each event is one JSON line; you'll see them as the job emits them.

## After it's running

A few habits worth getting into:

1. **Once a week**, check that the most recent `sync_done` event reports
   a reasonable `masterRows` and that `downloaded` >= 1 (otherwise the
   cache might be silently stale).
2. **Once a quarter**, prune `<cacheRoot>\ftp_raw\` — the cache grows
   unbounded as ICE renames files. A simple `del /q FTPCSD_PUB1_*_<old date>*`
   pattern keeps it manageable. We can wire this into the job later if it
   becomes a real concern.
3. **Once a year**, re-check the `cleartext_warning` — if ICE has by then
   enabled AUTH TLS on the FTP hosts, switch to
   `ice.ftp.FtpSession(TlsMode="strict")` to require encryption.
