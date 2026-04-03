<# 
YT_Agent_AllInOne.ps1
All-in-one local AI YouTube agent:
- Setup dependencies (ffmpeg, piper), folders, basic config
- Generate content pack using Ollama (title/desc/tags/script)
- Generate TTS using Piper
- Render video using FFmpeg (simple safe template)
- Write meta.json and update upload_queue.json for n8n
- Approve step to mark items PENDING for upload

Usage:
  pwsh -File F:\YouTubu_AI\YT_Agent_AllInOne.ps1 -Mode setup
  pwsh -File F:\YouTubu_AI\YT_Agent_AllInOne.ps1 -Mode generate -Channel EN
  pwsh -File F:\YouTubu_AI\YT_Agent_AllInOne.ps1 -Mode generate -Channel TE
  pwsh -File F:\YouTubu_AI\YT_Agent_AllInOne.ps1 -Mode approve -Channel EN -JobFolder "F:\YouTubu_AI\videos\review\EN\EN_20260224_231500"
#>

param(
  [ValidateSet("setup","generate","approve")]
  [string]$Mode = "generate",

  [ValidateSet("EN","TE")]
  [string]$Channel = "EN",

  [string]$JobFolder = ""
)

# -------------------------
# CONFIG (edit only this section if needed)
# -------------------------
$BASE = "F:\YouTubu_AI"

# Local tools install locations
$TOOLS = Join-Path $BASE "tools"
$FFMPEG_DIR = Join-Path $TOOLS "ffmpeg"
$PIPER_DIR  = Join-Path $TOOLS "piper"

# Ollama
$OLLAMA_EXE = "ollama"  # assumes in PATH after install
$OLLAMA_MODEL = "llama3.1:8b"

# Piper binaries & voice models (you can replace with what you download)
$PIPER_EXE = Join-Path $PIPER_DIR "piper.exe"
$PIPER_VOICE_EN = Join-Path $PIPER_DIR "en_US-amy-medium.onnx"
$PIPER_VOICE_TE = Join-Path $PIPER_DIR "te_IN-voice.onnx"  # rename to your actual Telugu onnx model file

# Folder structure
$TRENDS_DIR  = Join-Path $BASE "trends"
$VIDEOS_DIR  = Join-Path $BASE "videos"
$REVIEW_DIR  = Join-Path $VIDEOS_DIR "review"
$APPROVED_DIR= Join-Path $VIDEOS_DIR "approved"
$UPLOADED_DIR= Join-Path $VIDEOS_DIR "uploaded"

# n8n queue (your current project uses /output/upload_queue.json)
$OUTPUT_DIR = Join-Path $BASE "output"
$QUEUE_PATH = Join-Path $OUTPUT_DIR "upload_queue.json"

# Docker path mapping (you have F:\YouTubu_AI mounted as /data)
function To-DockerPath([string]$winPath) {
  # Convert "F:\YouTubu_AI\..." => "/data/..."
  $p = $winPath.Replace("$BASE", "/data")
  $p = $p.Replace("\","/")
  return $p
}

# -------------------------
# Helpers
# -------------------------
function Ensure-Dir([string]$p) {
  if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Fail([string]$msg) {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  exit 1
}

function Find-Exe([string]$exeName, [string]$fallback) {
  $cmd = Get-Command $exeName -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if ($fallback -and (Test-Path $fallback)) { return $fallback }
  return $null
}

function Download-Zip([string]$url, [string]$zipPath, [string]$extractTo) {
  Write-Host "Downloading: $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath
  Ensure-Dir $extractTo
  Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force
  Remove-Item $zipPath -Force
}

function Read-Json([string]$path) {
  if (!(Test-Path $path)) { return $null }
  return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Write-Json([string]$path, $obj, [int]$depth=50) {
  ($obj | ConvertTo-Json -Depth $depth) | Set-Content -Path $path -Encoding UTF8
}

function Get-RandomTopic([string]$topicFile) {
  if (!(Test-Path $topicFile)) { Fail "Topic file not found: $topicFile" }
  $lines = Get-Content $topicFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  if ($lines.Count -lt 1) { Fail "No topics found in: $topicFile" }
  return Get-Random $lines
}

function Ollama-GenerateJson([string]$prompt) {
  $ollama = Find-Exe $OLLAMA_EXE $null
  if (-not $ollama) { Fail "Ollama not found in PATH. Install Ollama, then run: ollama pull $OLLAMA_MODEL" }

  # Ensure model exists (best effort; if already there, it’s quick)
  & $ollama pull $OLLAMA_MODEL | Out-Null

  # Generate
  $raw = & $ollama run $OLLAMA_MODEL $prompt

  # Try to extract JSON object from output
  $text = $raw | Out-String
  $start = $text.IndexOf("{")
  $end = $text.LastIndexOf("}")
  if ($start -lt 0 -or $end -le $start) {
    Fail "LLM did not return JSON. Raw output saved in job folder."
  }
  $jsonText = $text.Substring($start, $end-$start+1)

  try { return ($jsonText | ConvertFrom-Json) }
  catch { Fail "Failed to parse JSON from LLM output." }
}

function Piper-TTS([string]$voiceModel, [string]$textPath, [string]$outWav) {
  if (!(Test-Path $PIPER_EXE)) { Fail "Piper exe not found: $PIPER_EXE" }
  if (!(Test-Path $voiceModel)) { Fail "Piper voice model not found: $voiceModel" }
  if (!(Test-Path $textPath)) { Fail "Script text not found: $textPath" }

  $txt = Get-Content $textPath -Raw
  $p = Start-Process -FilePath $PIPER_EXE -ArgumentList @("--model",$voiceModel,"--output_file",$outWav) -NoNewWindow -PassThru -RedirectStandardOutput "$outWav.log" -RedirectStandardError "$outWav.err" -Wait -ErrorAction SilentlyContinue
  # Piper reads from STDIN in many builds; some builds accept a file. We'll pipe text to stdin via cmd:
  # fallback approach:
  if (!(Test-Path $outWav) -or (Get-Item $outWav).Length -lt 1000) {
    # stdin pipe method
    $cmd = "type `"$textPath`" | `"$PIPER_EXE`" --model `"$voiceModel`" --output_file `"$outWav`""
    cmd /c $cmd | Out-Null
  }

  if (!(Test-Path $outWav) -or (Get-Item $outWav).Length -lt 1000) {
    Fail "Piper failed to produce WAV. Check: $outWav.log and $outWav.err"
  }
}

function Ensure-FFmpeg() {
  $ff = Find-Exe "ffmpeg" (Join-Path $FFMPEG_DIR "bin\ffmpeg.exe")
  if ($ff) { return $ff }
  return $null
}

function Render-Video([string]$ffmpeg, [string]$wav, [string]$outMp4, [string]$title) {

  if (!(Test-Path $wav)) { Fail "WAV not found: $wav" }

  # Clean title to avoid breaking ffmpeg drawtext
  $cleanTitle = $title -replace "'", ""
  $cleanTitle = $cleanTitle -replace '"', ""
  $cleanTitle = $cleanTitle -replace ":", "-"
  $cleanTitle = $cleanTitle -replace "\\", ""
  $cleanTitle = $cleanTitle -replace "/", ""

  # Build drawtext filter safely
  $draw = "drawtext=fontfile=C\:/Windows/Fonts/arial.ttf:text='$cleanTitle':fontcolor=white:fontsize=44:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=20"

  & $ffmpeg -y `
    -f lavfi -i "color=c=black:s=1280x720:r=30" `
    -i $wav `
    -vf $draw `
    -shortest `
    -c:v libx264 -pix_fmt yuv420p `
    -c:a aac -b:a 192k `
    $outMp4 | Out-Null

  if (!(Test-Path $outMp4) -or (Get-Item $outMp4).Length -lt 50000) {
    Fail "FFmpeg failed to produce MP4: $outMp4"
  }
}

function Init-QueueIfMissing() {
  Ensure-Dir $OUTPUT_DIR
  if (!(Test-Path $QUEUE_PATH)) {
    $q = [pscustomobject]@{
      count = 0
      generatedAt = (Get-Date)
      items = @()
    }
    Write-Json $QUEUE_PATH $q
  }
}

function Queue-AddItem($item) {
  Init-QueueIfMissing
  $q = Read-Json $QUEUE_PATH
  if (-not $q) { Fail "Could not read queue: $QUEUE_PATH" }

  # Ensure consistent optional fields exist
  foreach ($p in @("notes","startedAt","finishedAt","thumbnailPath","chaptersText")) {
    if (-not ($item.PSObject.Properties.Name -contains $p)) {
      $item | Add-Member -NotePropertyName $p -NotePropertyValue $null
    }
  }

  $q.items += $item
  $q.count = $q.items.Count
  $q.generatedAt = (Get-Date)
  Write-Json $QUEUE_PATH $q
}

function Queue-MarkApproved([string]$jobDir, [string]$channel) {
  Init-QueueIfMissing
  $q = Read-Json $QUEUE_PATH
  if (-not $q) { Fail "Could not read queue: $QUEUE_PATH" }

  $found = $false
  foreach ($it in $q.items) {
    if ($it.channel -eq $channel -and $it.jobDir -eq $jobDir) {
      $it.status = "PENDING"
      if (-not ($it.PSObject.Properties.Name -contains "notes")) { $it | Add-Member -NotePropertyName notes -NotePropertyValue "" }
      $it.notes = "Approved by user"
      $found = $true
      break
    }
  }
  if (-not $found) { Fail "Queue item not found for jobDir=$jobDir channel=$channel" }

  $q.generatedAt = (Get-Date)
  Write-Json $QUEUE_PATH $q
}

# -------------------------
# MODE: setup
# -------------------------
if ($Mode -eq "setup") {
  Write-Host "== SETUP START ==" -ForegroundColor Cyan

  # Folders
  Ensure-Dir $TOOLS
  Ensure-Dir $TRENDS_DIR
  Ensure-Dir $VIDEOS_DIR
  Ensure-Dir $REVIEW_DIR
  Ensure-Dir $APPROVED_DIR
  Ensure-Dir $UPLOADED_DIR
  Ensure-Dir (Join-Path $REVIEW_DIR "EN")
  Ensure-Dir (Join-Path $REVIEW_DIR "TE")
  Ensure-Dir (Join-Path $APPROVED_DIR "EN")
  Ensure-Dir (Join-Path $APPROVED_DIR "TE")
  Ensure-Dir (Join-Path $UPLOADED_DIR "EN")
  Ensure-Dir (Join-Path $UPLOADED_DIR "TE")
  Ensure-Dir $OUTPUT_DIR

  # Create topic files if missing
  $enTopics = Join-Path $TRENDS_DIR "EN_topics.txt"
  $teTopics = Join-Path $TRENDS_DIR "TE_topics.txt"
  if (!(Test-Path $enTopics)) { "AI jobs 2030 truth`nBest AI tools 2026`n" | Set-Content $enTopics -Encoding UTF8 }
  if (!(Test-Path $teTopics)) { "AI వల్ల ఉద్యోగాలు 2030లో ఏమవుతాయి`nఉపయోగపడే AI టూల్స్`n" | Set-Content $teTopics -Encoding UTF8 }

  # FFmpeg download (Windows build zip)
  if (!(Test-Path (Join-Path $FFMPEG_DIR "bin\ffmpeg.exe"))) {
    Ensure-Dir $FFMPEG_DIR
    $zip = Join-Path $TOOLS "ffmpeg.zip"
    # NOTE: This URL may change over time. If it fails, download ffmpeg and place into tools\ffmpeg manually.
    $url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    try {
      Download-Zip $url $zip $FFMPEG_DIR
      # Flatten: find ffmpeg.exe in extracted tree and create bin folder link structure
      $ff = Get-ChildItem $FFMPEG_DIR -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
      if ($ff) {
        $bin = Join-Path $FFMPEG_DIR "bin"
        Ensure-Dir $bin
        Copy-Item $ff.FullName (Join-Path $bin "ffmpeg.exe") -Force
      }
    } catch {
      Write-Host "FFmpeg download failed. Install ffmpeg manually and ensure ffmpeg.exe exists in $FFMPEG_DIR\bin" -ForegroundColor Yellow
    }
  }

  # Piper setup placeholder
  if (!(Test-Path $PIPER_EXE)) {
    Ensure-Dir $PIPER_DIR
    Write-Host "Piper not found. Place piper.exe + voice models here:" -ForegroundColor Yellow
    Write-Host "  $PIPER_DIR" -ForegroundColor Yellow
    Write-Host "Expected files:" -ForegroundColor Yellow
    Write-Host "  $PIPER_EXE"
    Write-Host "  $PIPER_VOICE_EN"
    Write-Host "  $PIPER_VOICE_TE"
  }

  # Ollama check
  $oll = Find-Exe $OLLAMA_EXE $null
  if (-not $oll) {
    Write-Host "Ollama not found in PATH. Install Ollama (Windows) and then run:" -ForegroundColor Yellow
    Write-Host "  ollama pull $OLLAMA_MODEL" -ForegroundColor Yellow
  } else {
    Write-Host "Ollama detected: $oll" -ForegroundColor Green
    & $oll pull $OLLAMA_MODEL | Out-Null
  }

  # Queue init
  Init-QueueIfMissing

  Write-Host "== SETUP DONE ==" -ForegroundColor Cyan
  Write-Host "Next: pwsh -File $BASE\YT_Agent_AllInOne.ps1 -Mode generate -Channel EN"
  exit 0
}

# -------------------------
# MODE: generate
# -------------------------
if ($Mode -eq "generate") {
  Write-Host "== GENERATE START ($Channel) ==" -ForegroundColor Cyan

  $topicFile = Join-Path $TRENDS_DIR "${Channel}_topics.txt"
  $topic = Get-RandomTopic $topicFile
  Write-Host "Topic picked: $topic" -ForegroundColor Green

  $rules = if ($Channel -eq "EN") {
@"
EdgeViralHub (English only). Style: energetic, simple, story-like but factual.
Length: 4–6 minutes voiceover.
No copyrighted lyrics, no brand claims, no medical/legal advice. No hate, no harassment.
Output must be ORIGINAL.
"@
  } else {
@"
ManaTelugodu (Telugu only). Style: natural Telugu (not direct translation).
Length: 4–6 minutes voiceover.
No copyrighted lyrics. No hate, no harassment. Keep culturally natural.
Output must be ORIGINAL.
"@
  }

  $prompt = @"
Return ONLY VALID JSON (no markdown) with fields:
title (string),
description (string),
tags (array of strings),
script (string),
thumbnailText (string)

RULES:
$rules

TOPIC:
$topic
"@

  # Prepare job folder
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $jobDir = Join-Path (Join-Path $REVIEW_DIR $Channel) "${Channel}_$ts"
  Ensure-Dir $jobDir

  # LLM -> package
  try {
    $pkg = Ollama-GenerateJson $prompt
  } catch {
    $rawPath = Join-Path $jobDir "ollama_raw.txt"
    $_ | Out-String | Set-Content $rawPath -Encoding UTF8
    Fail "LLM generation failed. See: $rawPath"
  }

  # Save text assets
  $scriptPath = Join-Path $jobDir "script.txt"
  ($pkg.script | Out-String).Trim() | Set-Content $scriptPath -Encoding UTF8

  $title = ($pkg.title | Out-String).Trim()
  if (-not $title) { $title = $topic }

  # TTS
  $wavPath = Join-Path $jobDir "voice.wav"
  $voiceModel = if ($Channel -eq "EN") { $PIPER_VOICE_EN } else { $PIPER_VOICE_TE }
  Piper-TTS $voiceModel $scriptPath $wavPath

  # Video render
  $ffmpeg = Ensure-FFmpeg
  if (-not $ffmpeg) { Fail "FFmpeg not found. Run setup or install FFmpeg." }
  $mp4Path = Join-Path $jobDir "video.mp4"
  Render-Video $ffmpeg $wavPath $mp4Path $title

  # Meta for review
  $metaPath = Join-Path $jobDir "meta.json"
  $meta = [pscustomobject]@{
    channel = $Channel
    topic = $topic
    title = $title
    description = ($pkg.description | Out-String).Trim()
    tags = @($pkg.tags)
    thumbnailText = ($pkg.thumbnailText | Out-String).Trim()
    status = "READY_FOR_REVIEW"
    approved = $false
    # Windows and Docker paths
    videoPath = $mp4Path
    videoPathDocker = To-DockerPath $mp4Path
    seoJsonPath = (Join-Path $jobDir "seo.json")
    seoJsonPathDocker = To-DockerPath (Join-Path $jobDir "seo.json")
    jobDir = $jobDir
    jobDirDocker = To-DockerPath $jobDir
    createdAt = (Get-Date).ToString("o")
    notes = ""
  }
  # Save SEO json (n8n can read)
  Write-Json $meta.seoJsonPath $meta
  Write-Json $metaPath $meta

  # Add to upload queue but NOT pending (review first)
  $queueItem = [pscustomobject]@{
    channel = $Channel
    status = "READY_FOR_REVIEW"
    videoPath = $meta.videoPathDocker   # for n8n inside docker
    seoJsonPath = $meta.seoJsonPathDocker
    title = $meta.title
    description = $meta.description
    tags = $meta.tags
    thumbnailPath = $null
    thumbnailText = $meta.thumbnailText
    chaptersText = ""
    createdAt = $meta.createdAt
    baseName = "${Channel}_$ts"
    jobDir = $meta.jobDirDocker
    notes = "Waiting for approval"
    startedAt = $null
    finishedAt = $null
  }
  Queue-AddItem $queueItem

  Write-Host "== GENERATED REVIEW PACKAGE ==" -ForegroundColor Cyan
  Write-Host "Job folder: $jobDir" -ForegroundColor Green
  Write-Host "Review video: $mp4Path" -ForegroundColor Green
  Write-Host "Approve with:" -ForegroundColor Yellow
  Write-Host "  pwsh -File $BASE\YT_Agent_AllInOne.ps1 -Mode approve -Channel $Channel -JobFolder `"$jobDir`"" -ForegroundColor Yellow
  exit 0
}

# -------------------------
# MODE: approve
# -------------------------
if ($Mode -eq "approve") {
  if (-not $JobFolder) { Fail "Provide -JobFolder path to approve." }
  if (!(Test-Path $JobFolder)) { Fail "JobFolder not found: $JobFolder" }

  $metaPath = Join-Path $JobFolder "meta.json"
  if (!(Test-Path $metaPath)) { Fail "meta.json not found in JobFolder: $metaPath" }

  $meta = Read-Json $metaPath
  $meta.approved = $true
  $meta.status = "APPROVED"
  $meta.notes = "Approved by user"
  Write-Json $metaPath $meta
  # also update seo json
  $seo = Read-Json (Join-Path $JobFolder "seo.json")
  if ($seo) {
    $seo.approved = $true
    $seo.status = "APPROVED"
    $seo.notes = "Approved by user"
    Write-Json (Join-Path $JobFolder "seo.json") $seo
  }

  # mark queue item as PENDING (n8n QueuePop expects PENDING)
  $jobDocker = To-DockerPath $JobFolder
  Queue-MarkApproved $jobDocker $Channel

  Write-Host "== APPROVED ==" -ForegroundColor Cyan
  Write-Host "Approved JobFolder: $JobFolder" -ForegroundColor Green
  Write-Host "Queue item moved to PENDING. Run your n8n upload workflow now." -ForegroundColor Green
  exit 0
}

Fail "Unknown mode."