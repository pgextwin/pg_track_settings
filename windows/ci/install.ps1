[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$control = Join-Path $UpstreamDir "pg_track_settings.control"
$extensionDir = Join-Path $PgRoot "share\extension"

if (-not (Test-Path $control -PathType Leaf)) {
    throw "Required pg_track_settings file was not found: $control"
}
if (-not (Test-Path $extensionDir -PathType Container)) {
    throw "PostgreSQL extension directory was not found: $extensionDir"
}

$sqlFiles = @(Get-ChildItem -Path $UpstreamDir -File -Filter "pg_track_settings--*.sql")
if ($sqlFiles.Count -ne 12) {
    throw "Expected 12 pg_track_settings SQL files, found $($sqlFiles.Count)."
}

Copy-Item $control (Join-Path $extensionDir "pg_track_settings.control") -Force
foreach ($sqlFile in $sqlFiles) {
    Copy-Item $sqlFile.FullName (Join-Path $extensionDir $sqlFile.Name) -Force
}

Write-Host "Installed SQL-only pg_track_settings control and $($sqlFiles.Count) SQL files into $extensionDir"
