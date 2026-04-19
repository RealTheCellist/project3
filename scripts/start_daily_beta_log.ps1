param(
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Dir = 'data'
)

$header = 'timestamp,tester,device,scenario,step,analyze_ok,stt_ok,fallback_used,latency_ms,outcome,note'
if (-not (Test-Path $Dir)) {
  New-Item -ItemType Directory -Path $Dir | Out-Null
}

$path = Join-Path $Dir "beta_run_log_$Date.csv"
if (-not (Test-Path $path)) {
  Set-Content -Path $path -Value $header -Encoding UTF8
  Write-Output "created: $path"
} else {
  Write-Output "exists: $path"
}
