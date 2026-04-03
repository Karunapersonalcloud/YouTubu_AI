$ErrorActionPreference = "Stop"
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

# Try to find ffmpeg inside common winget install locations
$candidates = @(
  "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
  "C:\Program Files\FFmpeg\bin\ffmpeg.exe",
  "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
  "C:\ffmpeg\bin\ffmpeg.exe"
)

$ff = $null

foreach ($c in $candidates) {
  if ($c -like "*WinGet\Packages") {
    $hit = Get-ChildItem -Path $c -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($hit) { $ff = $hit.FullName; break }
  } else {
    if (Test-Path $c) { $ff = $c; break }
  }
}

if (-not $ff) {
  Warn "ffmpeg.exe not found. Installing via winget..."
  winget install -e --id Gyan.FFmpeg
  Warn "Close PowerShell, reopen, then run: ffmpeg -version"
  exit 0
}

OK "Found ffmpeg at: $ff"

# Add its folder to USER PATH
$dir = Split-Path $ff -Parent
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dir*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
  OK "Added to USER PATH: $dir"
} else {
  OK "Already in USER PATH: $dir"
}

Warn "IMPORTANT: Close this PowerShell window and open a NEW PowerShell window."
Warn "Then verify: ffmpeg -version"