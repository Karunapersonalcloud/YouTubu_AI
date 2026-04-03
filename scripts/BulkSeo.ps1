<#
BulkSeo.ps1 (Upgraded)
- Scans EN + TE folders for MP4 files
- Generates SEO pack JSON per video using SeoPack.ps1
- Writes output JSON + optional title/desc/tags txt bundle
- Moves processed MP4s to processed folders (if -MoveProcessed)
- Writes CSV log (output\bulk_log.csv)

Default folders:
  VideosEN = F:\YouTubu_AI\videos\EN
  VideosTE = F:\YouTubu_AI\videos\TE
  ProcessedEN = F:\YouTubu_AI\videos\processed\EN
  ProcessedTE = F:\YouTubu_AI\videos\processed\TE
  OutEN = F:\YouTubu_AI\output\EN
  OutTE = F:\YouTubu_AI\output\TE
  LogCsv = F:\YouTubu_AI\output\bulk_log.csv
#>

[CmdletBinding()]
param(
  [string]$SeoPackPath = "F:\YouTubu_AI\scripts\SeoPack.ps1",

  [string]$VideosEN = "F:\YouTubu_AI\videos\EN",
  [string]$VideosTE = "F:\YouTubu_AI\videos\TE",

  [string]$ProcessedEN = "F:\YouTubu_AI\videos\processed\EN",
  [string]$ProcessedTE = "F:\YouTubu_AI\videos\processed\TE",

  [string]$OutEN = "F:\YouTubu_AI\output\EN",
  [string]$OutTE = "F:\YouTubu_AI\output\TE",

  [string]$LogCsv = "F:\YouTubu_AI\output\bulk_log.csv",

  [switch]$WriteTxtFiles,
  [switch]$SkipIfExists,

  # NEW: move MP4 after successful generation
  [switch]$MoveProcessed
)

function Ensure-Dir([string]$p) {
  New-Item -ItemType Directory -Force $p | Out-Null
}

function Has-Telugu([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return $false }
  return [regex]::IsMatch($text, '[\u0C00-\u0C7F]')
}

function Clean-KeywordFromFilename([string]$baseName) {
  $s = $baseName
  $s = $s -replace '[_\-]+', ' '
  $s = $s -replace '\s+', ' '
  $s = $s.Trim()

  # Remove common junk tokens (customize as needed)
  $s = $s -replace '\b(final|v\d+|version\d+|render|1080p|4k|hdr|shorts|reel|yt|youtube)\b', ''
  $s = $s -replace '\s+', ' '
  return $s.Trim()
}

function Extract-Year([string]$text) {
  $m = [regex]::Match($text, '\b(19\d{2}|20\d{2})\b')
  if ($m.Success) { return [int]$m.Value }
  return $null
}

function Default-ChaptersJsonEN {
  @(
    @{ time="00:00"; title="Intro" },
    @{ time="01:10"; title="The Reality" },
    @{ time="05:00"; title="The Risk" },
    @{ time="09:00"; title="What To Do" }
  ) | ConvertTo-Json -Compress
}

function Default-ChaptersJsonTE {
  @(
    @{ time="00:00"; title="ఇంట్రో" },
    @{ time="01:10"; title="అసలు విషయం" },
    @{ time="05:00"; title="ఎవరికీ ఇంపాక్ట్?" },
    @{ time="09:00"; title="మనము ఏం చేయాలి" }
  ) | ConvertTo-Json -Compress
}

function Write-TxtBundle([pscustomobject]$seo, [string]$outBasePathNoExt) {
  $seo.title | Out-File -Encoding utf8 ($outBasePathNoExt + ".title.txt")
  $seo.description | Out-File -Encoding utf8 ($outBasePathNoExt + ".desc.txt")
  ($seo.tags -join ", ") | Out-File -Encoding utf8 ($outBasePathNoExt + ".tags.txt")
}

function Ensure-LogHeader([string]$csvPath) {
  if (-not (Test-Path $csvPath)) {
    "timestamp,channel,inputFile,outputJson,safetyOk,safetyReason,status,notes" |
      Out-File -Encoding utf8 $csvPath
  }
}

function Append-LogRow(
  [string]$csvPath,
  [string]$channel,
  [string]$inputFile,
  [string]$outputJson,
  [bool]$safetyOk,
  [string]$safetyReason,
  [string]$status,
  [string]$notes
) {
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $row = @(
    $ts,
    $channel,
    $inputFile,
    $outputJson,
    $safetyOk,
    ('"' + ($safetyReason -replace '"','""') + '"'),
    $status,
    ('"' + ($notes -replace '"','""') + '"')
  ) -join ","
  Add-Content -Encoding utf8 -Path $csvPath -Value $row
}

function Move-ProcessedFile([System.IO.FileInfo]$file, [string]$processedDir) {
  Ensure-Dir $processedDir
  # Prevent double extension like .mp4.mp4
$name = $file.Name -replace '\.mp4\.mp4$', '.mp4'
$dest = Join-Path $processedDir $name

  # If same name exists, add timestamp suffix
  if (Test-Path $dest) {
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $dest = Join-Path $processedDir ("{0}_{1}{2}" -f $file.BaseName, $stamp, $file.Extension)
  }

  Move-Item -LiteralPath $file.FullName -Destination $dest -Force
  return $dest
}

function Generate-ForFileEN([System.IO.FileInfo]$file) {
  $base = $file.BaseName
  $outJson = Join-Path $OutEN ($base + ".json")

if ($SkipIfExists -and (Test-Path $outJson)) {
  # Still move the MP4 if requested, even if SEO already exists
  $movedTo = ""
  if ($MoveProcessed) {
    $movedTo = Move-ProcessedFile -file $file -processedDir $ProcessedEN
  }
  Append-LogRow -csvPath $LogCsv -channel "EN" -inputFile $file.FullName -outputJson $outJson `
    -safetyOk $true -safetyReason "SKIPPED: output exists" -status "SKIPPED" -notes ($movedTo ? "MovedTo=$movedTo" : "")
  if ($MoveProcessed -and $movedTo) { Write-Host "Moved EN -> $movedTo" }
  return
}

  $kw = Clean-KeywordFromFilename $base
  if (-not $kw) { $kw = "AI" }

  $yr = Extract-Year $kw
  $chap = Default-ChaptersJsonEN

  $args = @(
    "-File", $SeoPackPath,
    "-Channel", "EN",
    "-PrimaryKeyword", $kw,
    "-ChaptersJson", $chap
  )
  if ($yr) { $args += @("-Year", "$yr") }

  try {
    $jsonText = & pwsh @args
    $seo = $jsonText | ConvertFrom-Json
  } catch {
    Append-LogRow -csvPath $LogCsv -channel "EN" -inputFile $file.FullName -outputJson $outJson `
      -safetyOk $false -safetyReason "ERROR generating SEO" -status "ERROR" -notes $_.Exception.Message
    Write-Warning "ERROR EN: $($file.Name) => $($_.Exception.Message)"
    return
  }

  if (-not $seo.safety.ok) {
    Append-LogRow -csvPath $LogCsv -channel "EN" -inputFile $file.FullName -outputJson $outJson `
      -safetyOk $false -safetyReason $seo.safety.reason -status "FAILED_SAFETY" -notes ""
    Write-Warning "SKIP (Safety failed) EN: $($file.Name) => $($seo.safety.reason)"
    return
  }

  $jsonText | Out-File -Encoding utf8 $outJson

  if ($WriteTxtFiles) {
    $outBase = Join-Path $OutEN $base
    Write-TxtBundle -seo $seo -outBasePathNoExt $outBase
  }

  $movedTo = ""
  if ($MoveProcessed) {
    try {
      $movedTo = Move-ProcessedFile -file $file -processedDir $ProcessedEN
    } catch {
      $movedTo = ""
      Write-Warning "Generated SEO but failed to move EN file: $($file.Name) => $($_.Exception.Message)"
    }
  }

  Append-LogRow -csvPath $LogCsv -channel "EN" -inputFile $file.FullName -outputJson $outJson `
    -safetyOk $true -safetyReason $seo.safety.reason -status "OK" -notes ($movedTo ? "MovedTo=$movedTo" : "")

  Write-Host "OK EN -> $outJson"
  if ($MoveProcessed -and $movedTo) { Write-Host "Moved EN -> $movedTo" }
}

function Generate-ForFileTE([System.IO.FileInfo]$file) {
  $base = $file.BaseName
  $outJson = Join-Path $OutTE ($base + ".json")

  if ($SkipIfExists -and (Test-Path $outJson)) {
    Append-LogRow -csvPath $LogCsv -channel "TE" -inputFile $file.FullName -outputJson $outJson `
      -safetyOk $true -safetyReason "SKIPPED: output exists" -status "SKIPPED" -notes ""
    return
  }

  $raw = Clean-KeywordFromFilename $base
  $topicTelugu = if (Has-Telugu $raw) { $raw } else { "AI వల్ల ఉద్యోగాలు" }
  $shock = if (Has-Telugu $raw) { "$topicTelugu గురించి నిజం ఏంటి?" } else { "2030 నాటికి ఉద్యోగాలపై AI ప్రభావం ఏంటి?" }

  $chap = Default-ChaptersJsonTE

  $args = @(
    "-File", $SeoPackPath,
    "-Channel", "TE",
    "-TopicTelugu", $topicTelugu,
    "-ShockStatement", $shock,
    "-ChaptersJson", $chap
  )

  try {
    $jsonText = & pwsh @args
    $seo = $jsonText | ConvertFrom-Json
  } catch {
    Append-LogRow -csvPath $LogCsv -channel "TE" -inputFile $file.FullName -outputJson $outJson `
      -safetyOk $false -safetyReason "ERROR generating SEO" -status "ERROR" -notes $_.Exception.Message
    Write-Warning "ERROR TE: $($file.Name) => $($_.Exception.Message)"
    return
  }

  if (-not $seo.safety.ok) {
    Append-LogRow -csvPath $LogCsv -channel "TE" -inputFile $file.FullName -outputJson $outJson `
      -safetyOk $false -safetyReason $seo.safety.reason -status "FAILED_SAFETY" -notes ""
    Write-Warning "SKIP (Safety failed) TE: $($file.Name) => $($seo.safety.reason)"
    return
  }

  $jsonText | Out-File -Encoding utf8 $outJson

  if ($WriteTxtFiles) {
    $outBase = Join-Path $OutTE $base
    Write-TxtBundle -seo $seo -outBasePathNoExt $outBase
  }

  $movedTo = ""
  if ($MoveProcessed) {
    try {
      $movedTo = Move-ProcessedFile -file $file -processedDir $ProcessedTE
    } catch {
      $movedTo = ""
      Write-Warning "Generated SEO but failed to move TE file: $($file.Name) => $($_.Exception.Message)"
    }
  }

  Append-LogRow -csvPath $LogCsv -channel "TE" -inputFile $file.FullName -outputJson $outJson `
    -safetyOk $true -safetyReason $seo.safety.reason -status "OK" -notes ($movedTo ? "MovedTo=$movedTo" : "")

  Write-Host "OK TE -> $outJson"
  if ($MoveProcessed -and $movedTo) { Write-Host "Moved TE -> $movedTo" }
}

# ---------- Main ----------
if (-not (Test-Path $SeoPackPath)) {
  throw "SeoPack.ps1 not found at: $SeoPackPath"
}

Ensure-Dir $OutEN
Ensure-Dir $OutTE
Ensure-Dir (Split-Path $LogCsv -Parent)
Ensure-LogHeader $LogCsv

if (Test-Path $VideosEN) {
  Get-ChildItem -Path $VideosEN -Filter *.mp4 -File | ForEach-Object { Generate-ForFileEN $_ }
} else {
  Write-Warning "EN videos folder not found: $VideosEN"
}

if (Test-Path $VideosTE) {
  Get-ChildItem -Path $VideosTE -Filter *.mp4 -File | ForEach-Object { Generate-ForFileTE $_ }
} else {
  Write-Warning "TE videos folder not found: $VideosTE"
}

Write-Host "DONE. Log: $LogCsv"