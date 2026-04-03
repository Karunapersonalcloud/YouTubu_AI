<#
BuildUploadQueue.ps1
Creates: F:\YouTubu_AI\output\upload_queue.json

Matches:
  Processed videos:
    F:\YouTubu_AI\videos\processed\EN\*.mp4
    F:\YouTubu_AI\videos\processed\TE\*.mp4

  SEO JSON:
    F:\YouTubu_AI\output\EN\*.json
    F:\YouTubu_AI\output\TE\*.json

Queue item includes:
- channel (EN/TE)
- videoPath
- seoJsonPath
- title, description, tags, thumbnailText, chaptersText
- status = PENDING
#>

[CmdletBinding()]
param(
  [string]$ProcessedEN = "F:\YouTubu_AI\videos\processed\EN",
  [string]$ProcessedTE = "F:\YouTubu_AI\videos\processed\TE",
  [string]$OutEN       = "F:\YouTubu_AI\output\EN",
  [string]$OutTE       = "F:\YouTubu_AI\output\TE",
  [string]$QueuePath   = "F:\YouTubu_AI\output\upload_queue.json",
  [string]$LogPath     = "F:\YouTubu_AI\output\upload_queue_log.csv",

  # Optional thumbnail folders (leave empty if you don't use thumbnails yet)
  [string]$ThumbEN     = "",
  [string]$ThumbTE     = "",

  # If true, includes items even when SEO JSON is missing (marked as MISSING_SEO)
  [switch]$IncludeMissingSeo
)

function Ensure-Dir([string]$p) {
  New-Item -ItemType Directory -Force $p | Out-Null
}

function Ensure-LogHeader([string]$csvPath) {
  if (-not (Test-Path $csvPath)) {
    "timestamp,channel,video,seoJson,status,notes" | Out-File -Encoding utf8 $csvPath
  }
}

function LogRow([string]$channel,[string]$video,[string]$seo,[string]$status,[string]$notes) {
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $row = @(
    $ts,
    $channel,
    $video,
    $seo,
    $status,
    ('"' + ($notes -replace '"','""') + '"')
  ) -join ","
  Add-Content -Encoding utf8 -Path $LogPath -Value $row
}

function Safe-BaseName([System.IO.FileInfo]$file) {
  # Handles weird names like AI_jobs_2030.mp4.mp4 => base should be AI_jobs_2030
  $name = $file.Name
  $name = $name -replace '\.mp4\.mp4$', '.mp4'
  return [System.IO.Path]::GetFileNameWithoutExtension($name)
}

function Find-Thumbnail([string]$thumbDir, [string]$baseName) {
  if ([string]::IsNullOrWhiteSpace($thumbDir)) { return $null }
  if (-not (Test-Path $thumbDir)) { return $null }

  $candidates = @(
    Join-Path $thumbDir ($baseName + ".png"),
    Join-Path $thumbDir ($baseName + ".jpg"),
    Join-Path $thumbDir ($baseName + ".jpeg"),
    Join-Path $thumbDir ($baseName + ".webp")
  )

  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

function Load-Seo([string]$seoPath) {
  try {
    return (Get-Content $seoPath -Raw | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Build-QueueForChannel(
  [string]$channel,
  [string]$processedDir,
  [string]$outSeoDir,
  [string]$thumbDir
) {
  $items = New-Object System.Collections.Generic.List[object]

  if (-not (Test-Path $processedDir)) {
    LogRow $channel $processedDir "" "NO_FOLDER" "Processed folder not found"
    return $items
  }

  Get-ChildItem -Path $processedDir -Filter *.mp4 -File | ForEach-Object {
    $video = $_
    $base  = Safe-BaseName $video

    # SEO JSON file naming:
    # EN currently may be "something.mp4.json" (as you saw)
    # TE is usually "something.json"
    $seo1 = Join-Path $outSeoDir ($base + ".json")
    $seo2 = Join-Path $outSeoDir ($video.Name + ".json")  # handles "AI_jobs_2030.mp4.json"
    $seoPath = $null

    if (Test-Path $seo1) { $seoPath = $seo1 }
    elseif (Test-Path $seo2) { $seoPath = $seo2 }

    if (-not $seoPath) {
      $status = "MISSING_SEO"
      $notes  = "No matching SEO JSON found"
      LogRow $channel $video.FullName "" $status $notes

      if ($IncludeMissingSeo) {
        $items.Add([pscustomobject]@{
          channel       = $channel
          status        = $status
          videoPath     = $video.FullName
          seoJsonPath   = $null
          title         = $null
          description   = $null
          tags          = @()
          thumbnailPath = (Find-Thumbnail $thumbDir $base)
          thumbnailText = $null
          chaptersText  = $null
          createdAt     = (Get-Date).ToString("o")
          baseName      = $base
        })
      }
      return
    }

    $seo = Load-Seo $seoPath
    if (-not $seo) {
      LogRow $channel $video.FullName $seoPath "BAD_SEO_JSON" "Failed to parse JSON"
      return
    }

    # Safety gate (extra protection)
    if ($seo.safety -and $seo.safety.ok -eq $false) {
      LogRow $channel $video.FullName $seoPath "FAILED_SAFETY" ($seo.safety.reason)
      return
    }

    $thumbPath = Find-Thumbnail $thumbDir $base

    $items.Add([pscustomobject]@{
      channel       = $channel
      status        = "PENDING"
      videoPath     = $video.FullName
      seoJsonPath   = $seoPath
      title         = $seo.title
      description   = $seo.description
      tags          = @($seo.tags)
      thumbnailPath = $thumbPath
      thumbnailText = $seo.thumbnailText
      chaptersText  = $seo.chaptersText
      createdAt     = (Get-Date).ToString("o")
      baseName      = $base
    })

    LogRow $channel $video.FullName $seoPath "PENDING" "Queued"
  }

  return $items
}

# ---- main ----
Ensure-Dir (Split-Path $QueuePath -Parent)
Ensure-Dir (Split-Path $LogPath -Parent)
Ensure-LogHeader $LogPath

$queue = New-Object System.Collections.Generic.List[object]

$enItems = Build-QueueForChannel -channel "EN" -processedDir $ProcessedEN -outSeoDir $OutEN -thumbDir $ThumbEN
$teItems = Build-QueueForChannel -channel "TE" -processedDir $ProcessedTE -outSeoDir $OutTE -thumbDir $ThumbTE

$enItems | ForEach-Object { $queue.Add($_) }
$teItems | ForEach-Object { $queue.Add($_) }

# Sort by createdAt (stable) then by channel
$final = $queue | Sort-Object channel, createdAt

$payload = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("o")
  count       = $final.Count
  items       = $final
}

$payload | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $QueuePath

Write-Host "OK. Queue file created:"
Write-Host "  $QueuePath"
Write-Host "Log:"
Write-Host "  $LogPath"
Write-Host ("Items queued: {0}" -f $final.Count)