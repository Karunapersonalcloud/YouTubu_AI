<#
YouTube SEO Pack Generator + Channel Safety Validator (PowerShell) — Single File (All Fixes)
Compatible with PowerShell 7.5+

Outputs (JSON):
- channel
- title
- description
- tags (array)
- thumbnailText
- chaptersText
- safety { ok, reason }

Channel:
  EN = EdgeViralHub (English only)
  TE = ManaTelugodu (Telugu only)

Safety:
  - EN payload must NOT contain Telugu characters
  - TE payload MUST contain Telugu characters
Telugu Unicode block: \u0C00–\u0C7F

Usage examples at bottom.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("EN","TE")]
  [string]$Channel,

  # English inputs
  [string]$PrimaryKeyword,
  [string]$Curiosity = "What Nobody Is Telling You",
  [string]$PowerWord = "Shocking Truth",
  [int]$Year = (Get-Date).Year,
  [string[]]$SupportKeywords,
  [string[]]$BroadTags,
  [string[]]$BulletsEN,

  # Telugu inputs
  [string]$TopicTelugu,
  [string]$ShockStatement,
  [string]$HookTelugu = "నిజం ఇదే!",
  [string[]]$SupportKeywordsTelugu,
  [string[]]$BroadTagsTelugu,
  [string[]]$BulletsTE,

  # Chapters (use either Chapters OR ChaptersJson)
  [object[]]$Chapters,
  [string]$ChaptersJson
)

# -------- Helpers --------

function Normalize-Spaces([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  return ($s -replace '\s+', ' ').Trim()
}

function Clamp-Words([string]$text, [int]$maxWords) {
  $t = Normalize-Spaces $text
  if (-not $t) { return "" }
  $words = $t.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($words.Count -le $maxWords) { return $t }
  return ($words[0..($maxWords-1)] -join ' ')
}

function Has-Telugu([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return $false }
  return [regex]::IsMatch($text, '[\u0C00-\u0C7F]')
}

function Unique-Tags([string[]]$tags) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  $out = New-Object 'System.Collections.Generic.List[string]'
  foreach ($t in $tags) {
    $n = Normalize-Spaces $t
    if (-not $n) { continue }
    $key = $n.ToLowerInvariant()
    if ($set.Add($key)) { $out.Add($n) }
  }
  return ,$out.ToArray()
}

function Build-ChaptersText([object[]]$chapters) {
  if (-not $chapters -or $chapters.Count -eq 0) { return "" }

  $lines = foreach ($c in $chapters) {
    # support hashtable, psobject, json objects
    $time  = $null
    $title = $null

    try {
      if ($c -is [hashtable]) {
        $time  = $c["time"]
        $title = $c["title"]
      } else {
        $time  = $c.time
        $title = $c.title
      }
    } catch {
      # ignore and skip
    }

    $time  = Normalize-Spaces ([string]$time)
    $title = Normalize-Spaces ([string]$title)

    if (-not $time) { $time = "00:00" }
    if ($title) { "$time $title" } else { $null }
  }

  return ($lines | Where-Object { $_ }) -join "`n"
}

function English-Title([string]$PrimaryKeyword, [string]$Curiosity, [string]$PowerWord, [int]$Year) {
  $pk = Normalize-Spaces $PrimaryKeyword
  if (-not $pk) { $pk = "AI" }

  $c = Normalize-Spaces $Curiosity
  if (-not $c) { $c = "What Nobody Is Telling You" }

  $p = Normalize-Spaces $PowerWord
  if (-not $p) { $p = "Shocking Truth" }

  $y = if ($Year) { $Year } else { (Get-Date).Year }

  $title = "$pk – $c – $p ($y)"
  return Clamp-Words $title 16
}

function Telugu-Title([string]$ShockStatement, [string]$HookTelugu, [int]$Year) {
  $ss = Normalize-Spaces $ShockStatement
  if (-not $ss) { $ss = "$Year నాటికి నిజంగా ఏమవుతుంది?" }

  $hk = Normalize-Spaces $HookTelugu
  if (-not $hk) { $hk = "నిజం ఇదే!" }

  $title = "$ss | $hk"
  return Clamp-Words $title 14
}

function English-Description([string]$PrimaryKeyword, [string[]]$BulletsEN, [string]$ChaptersText) {
  $pk = if ($PrimaryKeyword) { $PrimaryKeyword } else { "AI" }

  $b = if ($BulletsEN -and $BulletsEN.Count -ge 3) {
    $BulletsEN
  } else {
    @(
      "What’s changing (and why)",
      "Who is at risk and who wins",
      "What you should do next"
    )
  }

  if (-not $ChaptersText) {
    $ChaptersText = "00:00 Intro`n01:00 Key Idea`n03:00 Real Impact`n06:00 What to Do`n09:00 Summary"
  }

  return @"
${pk}: Here’s the real breakdown in simple terms.

What You’ll Learn:
• $($b[0])
• $($b[1])
• $($b[2])

Chapters:
$ChaptersText

Subscribe for AI + Business breakdowns (English).
#AI #Tech #Business
"@.Trim()
}

function Telugu-Description([string]$TopicTelugu, [string[]]$BulletsTE, [string]$ChaptersText) {
  $tt = if ($TopicTelugu) { $TopicTelugu } else { "టాపిక్" }

  $b = if ($BulletsTE -and $BulletsTE.Count -ge 3) {
    $BulletsTE
  } else {
    @(
      "ఇది ఎందుకు జరుగుతోంది?",
      "ఎవరికీ ఇంపాక్ట్ ఉంటుంది?",
      "మనము ఇప్పుడే ఏం చేయాలి?"
    )
  }

  if (-not $ChaptersText) {
    $ChaptersText = "00:00 ఇంట్రో`n01:00 అసలు విషయం`n03:00 నిజమైన ఇంపాక్ట్`n06:00 మనం ఏం చేయాలి`n09:00 సారాంశం"
  }

  return @"
${tt}: ఈ వీడియోలో సింపుల్‌గా క్లియర్‌గా చెప్తాను.

మీరు తెలుసుకునేది:
• $($b[0])
• $($b[1])
• $($b[2])

Chapters:
$ChaptersText

ఇలాంటి వీడియోల కోసం Subscribe చేయండి (తెలుగు).
#తెలుగు #AI #వైరల్
"@.Trim()
}

function English-Tags([string]$PrimaryKeyword, [string[]]$SupportKeywords, [string[]]$BroadTags) {
  $pk = if ($PrimaryKeyword) { $PrimaryKeyword } else { "AI" }
  $support = if ($SupportKeywords) { $SupportKeywords } else { @("future of work","AI automation impact","jobs replaced by AI") }
  $broad   = if ($BroadTags) { $BroadTags } else { @("technology news","business insights","future predictions") }
  return Unique-Tags (@($pk) + $support + $broad)
}

function Telugu-Tags([string]$TopicTelugu, [string[]]$SupportKeywordsTelugu, [string[]]$BroadTagsTelugu) {
  $tt = if ($TopicTelugu) { $TopicTelugu } else { "టాపిక్" }
  $support = if ($SupportKeywordsTelugu) { $SupportKeywordsTelugu } else { @("AI ప్రభావం","ఉద్యోగాలు 2030","భవిష్యత్ ఉద్యోగాలు") }
  $broad   = if ($BroadTagsTelugu) { $BroadTagsTelugu } else { @("తెలుగు ట్రెండింగ్","టెక్నాలజీ","వైరల్ వీడియో") }
  return Unique-Tags (@($tt) + $support + $broad)
}

function Thumbnail-TextEN { "80% GONE?" }
function Thumbnail-TextTE { "నిజం ఇదే!" }

function Validate-ChannelSafety([string]$Channel, [string]$Title, [string]$Description, [string[]]$Tags) {
  $all = "$Title $Description $($Tags -join ' ')"
  $telugu = Has-Telugu $all

  if ($Channel -eq "EN" -and $telugu) {
    return @{ ok=$false; reason="Detected Telugu characters in EN payload. Risk of uploading Telugu content to English channel." }
  }
  if ($Channel -eq "TE" -and (-not $telugu)) {
    return @{ ok=$false; reason="No Telugu characters detected in TE payload. Risk of uploading English content to Telugu channel." }
  }
  return @{ ok=$true; reason="Channel safety validation passed." }
}

# -------- Chapters JSON support (reliable from CLI/automation) --------
if ($ChaptersJson) {
  try {
    $Chapters = $ChaptersJson | ConvertFrom-Json
  } catch {
    throw "Invalid ChaptersJson. Provide a valid JSON array. Error: $($_.Exception.Message)"
  }
}

# -------- Build --------
$chaptersText = Build-ChaptersText $Chapters

if ($Channel -eq "EN") {
  $title = English-Title -PrimaryKeyword $PrimaryKeyword -Curiosity $Curiosity -PowerWord $PowerWord -Year $Year
  $desc  = English-Description -PrimaryKeyword $PrimaryKeyword -BulletsEN $BulletsEN -ChaptersText $chaptersText
  $tags  = English-Tags -PrimaryKeyword $PrimaryKeyword -SupportKeywords $SupportKeywords -BroadTags $BroadTags
  $thumb = Thumbnail-TextEN
}
else {
  $title = Telugu-Title -ShockStatement $ShockStatement -HookTelugu $HookTelugu -Year $Year
  $desc  = Telugu-Description -TopicTelugu $TopicTelugu -BulletsTE $BulletsTE -ChaptersText $chaptersText
  $tags  = Telugu-Tags -TopicTelugu $TopicTelugu -SupportKeywordsTelugu $SupportKeywordsTelugu -BroadTagsTelugu $BroadTagsTelugu
  $thumb = Thumbnail-TextTE
}

$safety = Validate-ChannelSafety -Channel $Channel -Title $title -Description $desc -Tags $tags

$result = [pscustomobject]@{
  channel       = $Channel
  title         = $title
  description   = $desc
  tags          = $tags
  thumbnailText = $thumb
  chaptersText  = $chaptersText
  safety        = $safety
}

# Print JSON to stdout (automation-friendly)
$result | ConvertTo-Json -Depth 8

<#
=========================
USAGE (Windows PC)
=========================

1) English (EdgeViralHub) with ChaptersJson (recommended):
$chap = @(
  @{ time = "00:00"; title = "Intro" },
  @{ time = "01:10"; title = "The Reality" },
  @{ time = "05:00"; title = "The Risk" },
  @{ time = "09:00"; title = "What To Do" }
) | ConvertTo-Json -Compress

pwsh -File "F:\YouTubu_AI\scripts\SeoPack.ps1" -Channel EN `
  -PrimaryKeyword "AI jobs 2030" `
  -Curiosity "What Nobody Is Telling You" `
  -PowerWord "Shocking Truth" `
  -Year 2030 `
  -SupportKeywords @("future of work","AI automation impact","jobs replaced by AI") `
  -ChaptersJson $chap

2) Telugu (ManaTelugodu) with ChaptersJson:
$chap = @(
  @{ time = "00:00"; title = "ఇంట్రో" },
  @{ time = "01:10"; title = "అసలు విషయం" },
  @{ time = "05:00"; title = "ఎవరికీ ఇంపాక్ట్?" },
  @{ time = "09:00"; title = "మనము ఏం చేయాలి" }
) | ConvertTo-Json -Compress

pwsh -File "F:\YouTubu_AI\scripts\SeoPack.ps1" -Channel TE `
  -TopicTelugu "AI వల్ల ఉద్యోగాలు" `
  -ShockStatement "2030 నాటికి 80% ఉద్యోగాలు పోతాయా?" `
  -HookTelugu "నిజం ఇదే!" `
  -SupportKeywordsTelugu @("AI ప్రభావం","ఉద్యోగాలు 2030","భవిష్యత్ ఉద్యోగాలు") `
  -ChaptersJson $chap

3) Minimal run (no chapters passed; defaults will be used):
pwsh -File "F:\YouTubu_AI\scripts\SeoPack.ps1" -Channel EN -PrimaryKeyword "AI jobs 2030"
pwsh -File "F:\YouTubu_AI\scripts\SeoPack.ps1" -Channel TE -TopicTelugu "AI వల్ల ఉద్యోగాలు" -ShockStatement "2030 నాటికి 80% ఉద్యోగాలు పోతాయా?"

#>