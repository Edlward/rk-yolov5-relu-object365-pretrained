<#
.SYNOPSIS
    Download and verify the RK YOLOv5 ReLU pretrained weights on Windows.

.DESCRIPTION
    Windows-friendly replacement for the bash + `sha256sum -c` flow described in
    README.md. Downloads the release assets into `weights/` and verifies every
    file against `release/SHA256SUMS` (the same list shipped in the v0.1.0 release).

.PARAMETER OutDir
    Target directory. Defaults to `<repo>/weights`.

.PARAMETER Pattern
    Wildcard filter applied to asset names, e.g. "yolov5n*" or "*coco*".
    Defaults to "*" (all six assets).

.PARAMETER BaseUrl
    Release download base URL. Override when using a mirror / proxy.

.PARAMETER VerifyOnly
    Skip downloading and only check the files already on disk.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1 -Pattern "yolov5n_*"

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1 -VerifyOnly
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$Pattern = "*",
    [string]$BaseUrl = "https://github.com/Edlward/rk-yolov5-relu-object365-pretrained/releases/download/v0.1.0",
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repoRoot "weights" }
$sumsFile = Join-Path $repoRoot "release/SHA256SUMS"

if (-not (Test-Path $sumsFile)) {
    Write-Error "SHA256SUMS not found: $sumsFile"
    exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# release/SHA256SUMS format: "<sha256>  <filename>"
$entries = @()
foreach ($line in Get-Content $sumsFile) {
    if ($line.Trim() -eq "") { continue }
    $parts = $line -split '\s+'
    $entries += [pscustomobject]@{ Name = $parts[1]; Sha256 = $parts[0].ToLower() }
}

$selected = $entries | Where-Object { $_.Name -like $Pattern }
if (-not $selected) {
    Write-Error "No asset in SHA256SUMS matches pattern '$Pattern'"
    exit 2
}

$failed = 0
foreach ($entry in $selected) {
    $dest = Join-Path $OutDir $entry.Name

    if (-not $VerifyOnly -and -not (Test-Path $dest)) {
        Write-Host "==> downloading $($entry.Name)"
        & curl.exe -L --fail --retry 3 --retry-delay 2 -o $dest "$BaseUrl/$($entry.Name)"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "download failed: $($entry.Name) (exit $LASTEXITCODE)"
            $failed++
            continue
        }
    }

    if (-not (Test-Path $dest)) {
        Write-Warning "missing: $($entry.Name)"
        $failed++
        continue
    }

    $actual = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $entry.Sha256) {
        Write-Host ("PASS  {0}" -f $entry.Name)
    }
    else {
        Write-Warning ("FAIL  {0}`n      expected={1}`n      actual  ={2}" -f $entry.Name, $entry.Sha256, $actual)
        $failed++
    }
}

Write-Host "----"
if ($failed -gt 0) {
    Write-Host "$failed asset(s) failed; see warnings above."
    exit 1
}
Write-Host "All $($selected.Count) asset(s) verified in: $OutDir"
