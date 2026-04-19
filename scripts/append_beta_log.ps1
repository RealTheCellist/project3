param(
  [Parameter(Mandatory = $true)][string]$Date,
  [Parameter(Mandatory = $true)][string]$Tester,
  [Parameter(Mandatory = $true)][string]$Device,
  [Parameter(Mandatory = $true)][string]$Scenario,
  [Parameter(Mandatory = $true)][string]$Step,
  [string]$AnalyzeOk = '',
  [string]$SttOk = '',
  [string]$FallbackUsed = '',
  [string]$LatencyMs = '',
  [ValidateSet('fast', 'balanced', 'accurate', '')][string]$Profile = '',
  [Parameter(Mandatory = $true)][ValidateSet('pass', 'fail')][string]$Outcome,
  [string]$Note = '',
  [string]$Dir = 'data'
)

function Get-ShortSha256([string]$Value) {
  $normalized = ($Value ?? '').Trim().ToLowerInvariant()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }
  $hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
  return $hex.Substring(0, 12)
}

$path = Join-Path $Dir "beta_run_log_$Date.csv"
if (-not (Test-Path $path)) {
  Write-Error "log file not found: $path. run scripts/start_daily_beta_log.ps1 first."
  exit 1
}

$ts = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
$finalNote = $Note
if ($Profile -ne '') {
  if ($finalNote -eq '') {
    $finalNote = "profile=$Profile"
  } else {
    $finalNote = "$finalNote; profile=$Profile"
  }
}

$testerHash = Get-ShortSha256 $Tester
$deviceHash = Get-ShortSha256 $Device
$header = (Get-Content -Path $path -TotalCount 1)
$hasAnonymizedColumns = $header -match 'tester_hash' -and $header -match 'device_hash'

if ($hasAnonymizedColumns) {
  $row = "$ts,$Tester,$Device,$Scenario,$Step,$AnalyzeOk,$SttOk,$FallbackUsed,$LatencyMs,$Outcome,$finalNote,$testerHash,$deviceHash"
} else {
  $row = "$ts,$Tester,$Device,$Scenario,$Step,$AnalyzeOk,$SttOk,$FallbackUsed,$LatencyMs,$Outcome,$finalNote"
}

Add-Content -Path $path -Value $row -Encoding UTF8
Write-Output "appended: $path"

