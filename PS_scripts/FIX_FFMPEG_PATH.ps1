# FIX_FFMPEG_PATH.ps1
# - Finds ffmpeg.exe
# - Adds its folder to Machine PATH (permanent)
# - Refreshes PATH for current session
# - Verifies ffmpeg works

$ErrorActionPreference = "Stop"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Err($m){ Write-Host $m -ForegroundColor Red }

Step "Searching for ffmpeg.exe..."

# 1) Try normal command resolution first
$cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($cmd) {
  OK "ffmpeg already available: $($cmd.Source)"
  exit 0
}

# 2) Search common install locations (Gyan FFmpeg / winget style)
$candidates = @(
  "C:\ffmpeg\bin\ffmpeg.exe",
  "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
  "C:\Program Files\Gyan\ffmpeg\bin\ffmpeg.exe",
  "C:\ProgramData\chocolatey\bin\ffmpeg.exe"
)

$ffmpegExe = $null
foreach($p in $candidates){
  if (Test-Path $p) { $ffmpegExe = $p; break }
}

# 3) If not found, do a quick drive scan (fast, limited depth)
if (-not $ffmpegExe) {
  Warn "Not found in common paths. Scanning C:\ for ffmpeg.exe (may take ~10-30s)..."
  $ffmpegExe = Get-ChildItem -Path "C:\" -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
}

if (-not $ffmpegExe) {
  Err "ffmpeg.exe not found. Reinstall with: winget install -e --id Gyan.FFmpeg"
  exit 1
}

OK "Found ffmpeg: $ffmpegExe"
$ffDir = Split-Path $ffmpegExe -Parent

# 4) Add to Machine PATH if missing
Step "Adding FFmpeg folder to Machine PATH (admin may be required)..."
$machinePath = [Environment]::GetEnvironmentVariable("Path","Machine")
if ($machinePath -and $machinePath.ToLower().Contains($ffDir.ToLower())) {
  OK "FFmpeg folder already in Machine PATH."
} else {
  try {
    $newPath = if ([string]::IsNullOrWhiteSpace($machinePath)) { $ffDir } else { "$machinePath;$ffDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    OK "Added to Machine PATH: $ffDir"
  } catch {
    Warn "Could not write Machine PATH (likely not Admin). Adding to User PATH instead..."
    $userPath = [Environment]::GetEnvironmentVariable("Path","User")
    if (-not $userPath.ToLower().Contains($ffDir.ToLower())) {
      [Environment]::SetEnvironmentVariable("Path", "$userPath;$ffDir", "User")
      OK "Added to User PATH: $ffDir"
    }
  }
}

# 5) Refresh PATH in current session
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

# 6) Verify
Step "Verifying..."
ffmpeg -version | Select-Object -First 1
OK "ffmpeg is now available in this shell."

Warn "If another PowerShell window is open, close and reopen it to pick up PATH."