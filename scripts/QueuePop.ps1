<#
QueuePop.ps1 (Fixed)
- Reads upload_queue.json
- Finds first item with status == PENDING
- Sets it to IN_PROGRESS
- Adds startedAt safely
- Writes next_upload.json (single item payload) for n8n to consume
#>

[CmdletBinding()]
param(
  [string]$QueuePath = "F:\YouTubu_AI\output\upload_queue.json",
  [string]$NextPath  = "F:\YouTubu_AI\output\next_upload.json"
)

if (-not (Test-Path $QueuePath)) { throw "Queue file not found: $QueuePath" }

$queue = Get-Content $QueuePath -Raw | ConvertFrom-Json

if (-not $queue.items -or $queue.items.Count -eq 0) {
  throw "Queue has no items."
}

# Find first PENDING
$idx = -1
for ($i=0; $i -lt $queue.items.Count; $i++) {
  if ($queue.items[$i].status -eq "PENDING") { $idx = $i; break }
}

if ($idx -lt 0) {
  $marker = [pscustomobject]@{ status="NO_PENDING"; generatedAt=(Get-Date).ToString("o") }
  $marker | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $NextPath
  Write-Host "NO_PENDING. Wrote: $NextPath"
  exit 0
}

$item = $queue.items[$idx]

# Update status safely
$item.status = "IN_PROGRESS"

# Add startedAt safely (works even if property doesn't exist)
$started = (Get-Date).ToString("o")
if ($item.PSObject.Properties.Match('startedAt').Count -gt 0) {
  $item.startedAt = $started
} else {
  $item | Add-Member -NotePropertyName startedAt -NotePropertyValue $started -Force
}

# Save queue back
$queue.generatedAt = (Get-Date).ToString("o")
$queue | ConvertTo-Json -Depth 15 | Out-File -Encoding utf8 $QueuePath

# Write next upload payload (single item)
$payload = [pscustomobject]@{
  status      = "READY"
  queueIndex  = $idx
  item        = $item
  generatedAt = (Get-Date).ToString("o")
}
$payload | ConvertTo-Json -Depth 15 | Out-File -Encoding utf8 $NextPath

Write-Host "READY. Wrote: $NextPath"
Write-Host ("Channel={0} Video={1}" -f $item.channel, $item.videoPath)