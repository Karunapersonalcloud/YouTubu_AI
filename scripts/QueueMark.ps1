<#
QueueMark.ps1 (Fixed)
- Updates an item in upload_queue.json by queueIndex
- Sets status DONE or FAILED
- Adds finishedAt and notes safely (even if properties don't exist)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [int]$QueueIndex,

  [Parameter(Mandatory=$true)]
  [ValidateSet("DONE","FAILED")]
  [string]$Status,

  [string]$Notes = "",

  [string]$QueuePath = "F:\YouTubu_AI\output\upload_queue.json"
)

if (-not (Test-Path $QueuePath)) { throw "Queue file not found: $QueuePath" }

$queue = Get-Content $QueuePath -Raw | ConvertFrom-Json

if (-not $queue.items -or $queue.items.Count -eq 0) {
  throw "Queue has no items."
}

if ($QueueIndex -lt 0 -or $QueueIndex -ge $queue.items.Count) {
  throw "QueueIndex out of range: $QueueIndex"
}

$item = $queue.items[$QueueIndex]

# Set status (existing property)
$item.status = $Status

# finishedAt safely
$finished = (Get-Date).ToString("o")
if ($item.PSObject.Properties.Match('finishedAt').Count -gt 0) {
  $item.finishedAt = $finished
} else {
  $item | Add-Member -NotePropertyName finishedAt -NotePropertyValue $finished -Force
}

# notes safely
if ($item.PSObject.Properties.Match('notes').Count -gt 0) {
  $item.notes = $Notes
} else {
  $item | Add-Member -NotePropertyName notes -NotePropertyValue $Notes -Force
}

# Save back
$queue.generatedAt = (Get-Date).ToString("o")
$queue | ConvertTo-Json -Depth 15 | Out-File -Encoding utf8 $QueuePath

Write-Host "UPDATED: index=$QueueIndex status=$Status"