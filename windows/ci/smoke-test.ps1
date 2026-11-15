[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [int]$PgPort,

    [Parameter(Mandatory = $true)]
    [int]$PostgreSqlMajor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PostgreSqlMajor -notin @(15, 16, 17, 18)) {
    throw "Unsupported PostgreSQL major for pg_track_settings: $PostgreSqlMajor"
}

$initdb = Join-Path $PgRoot "bin\initdb.exe"
$pgCtl = Join-Path $PgRoot "bin\pg_ctl.exe"
$pgIsReady = Join-Path $PgRoot "bin\pg_isready.exe"
$psql = Join-Path $PgRoot "bin\psql.exe"

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$dataDir = Join-Path $tempRoot "pg_track_settings-pg$PostgreSqlMajor-data"
$logFile = Join-Path $tempRoot "pg_track_settings-pg$PostgreSqlMajor.log"
$setupSql = Join-Path $tempRoot "pg_track_settings-pg$PostgreSqlMajor-setup.sql"

if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
}
if (Test-Path $logFile) {
    Remove-Item $logFile -Force
}

& $initdb -D $dataDir -U postgres -A trust --encoding=UTF8 --no-locale
if ($LASTEXITCODE -ne 0) {
    throw "initdb failed."
}

function Show-PostgresLog {
    if (Test-Path $logFile) {
        Write-Host "----- PostgreSQL log -----"
        Get-Content $logFile -Tail 300
        Write-Host "--------------------------"
    }
}

function Wait-Postgres {
    for ($i = 0; $i -lt 45; $i++) {
        & $pgIsReady -h 127.0.0.1 -p $PgPort -q
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 2
    }
    Show-PostgresLog
    throw "Temporary PostgreSQL cluster did not become ready."
}

$started = $false
try {
    $serverOptions = "-p $PgPort -c listen_addresses=127.0.0.1"
    & $pgCtl -D $dataDir -l $logFile -o $serverOptions start
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "Failed to start PostgreSQL for pg_track_settings smoke test."
    }
    $started = $true

    Wait-Postgres

    @'
CREATE EXTENSION pg_track_settings SCHEMA public;

SET work_mem = '10MB';
SELECT public.pg_track_settings_snapshot();
SELECT pg_catalog.pg_sleep(1);
SET work_mem = '5MB';
SELECT public.pg_track_settings_snapshot();
'@ | Set-Content -Path $setupSql -Encoding utf8

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -f $setupSql
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "pg_track_settings functional setup failed."
    }

    $currentWorkMem = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.pg_track_settings() WHERE name = 'work_mem' AND setting_pretty = '5MB';") | Select-Object -Last 1).Trim()
    $logCount = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.pg_track_settings_log('work_mem');") | Select-Object -Last 1).Trim()
    $diffCount = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "WITH logs AS (SELECT ts FROM public.pg_track_settings_log('work_mem')) SELECT count(*) FROM public.pg_track_settings_diff((SELECT min(ts) FROM logs), (SELECT max(ts) FROM logs)) WHERE name = 'work_mem' AND from_setting_pretty = '10MB' AND to_setting_pretty = '5MB';") | Select-Object -Last 1).Trim()
    $rebootCount = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.pg_track_reboot_log();") | Select-Object -Last 1).Trim()

    if ($currentWorkMem -ne "1") {
        throw "pg_track_settings() did not report work_mem = 5MB: got $currentWorkMem"
    }
    if ($logCount -ne "2") {
        throw "Expected 2 rows from pg_track_settings_log('work_mem'), got $logCount"
    }
    if ($diffCount -ne "1") {
        throw "pg_track_settings_diff() did not detect work_mem change from 10MB to 5MB: got $diffCount"
    }
    if ($rebootCount -ne "1") {
        throw "Expected 1 row from pg_track_reboot_log(), got $rebootCount"
    }

    $historyAfterReset = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT public.pg_track_settings_reset(); SELECT count(*) FROM public.pg_track_settings_history;") | Select-Object -Last 1).Trim()
    if ($historyAfterReset -ne "0") {
        throw "Expected 0 rows in pg_track_settings_history after pg_track_settings_reset(), got $historyAfterReset"
    }

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DROP EXTENSION pg_track_settings;"
    if ($LASTEXITCODE -ne 0) {
        throw "pg_track_settings smoke-test cleanup failed."
    }

    Write-Host "PASS: pg_track_settings PG$PostgreSqlMajor functional smoke test"
}
catch {
    Show-PostgresLog
    throw
}
finally {
    if ($started -or (Test-Path (Join-Path $dataDir "postmaster.pid"))) {
        & $pgCtl -D $dataDir -m fast stop
    }
    if (Test-Path $dataDir) {
        Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
