using namespace System.Net
param($Request, $TriggerMetadata, $PreviousCheckins)

function Send-Reply($Status, $Body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = $Status; Body = $Body })
}

$body = $Request.Body
if (-not $body -or -not $body.deviceName -or -not $body.checks) {
    Send-Reply ([HttpStatusCode]::BadRequest) 'deviceName and checks are required'
    return
}
# Only known platforms, so the value can never be used to read other files.
if ($body.platform -notin @('windows', 'macos')) {
    Send-Reply ([HttpStatusCode]::BadRequest) 'unknown platform'
    return
}

# Load the baseline for this platform.
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Join-Path $env:HOME 'site\wwwroot' }
$baselinePath = Join-Path $root "baselines\$($body.platform).json"
if (-not (Test-Path $baselinePath)) {
    Send-Reply ([HttpStatusCode]::BadRequest) 'no baseline for this platform'
    return
}
$baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json

# Index the reported checks by name.
$checks = @{}
foreach ($c in $body.checks) { $checks[$c.name] = $c }

# Evaluate every rule against what the device reported.
$failed = @()
foreach ($rule in $baseline.rules) {
    $check = $checks[$rule.check]
    $actual = if ($check -and $check.status -eq 'ok') { $check.value.($rule.field) } else { 'check-error' }
    $isNumber = ($actual -is [ValueType]) -and ($actual -isnot [bool])
    $pass = switch ($rule.type) {
        'equals' { $actual -eq $rule.expected }
        'max'    { $isNumber -and ($actual -le $rule.expected) }
        default  { $false }
    }
    if (-not $pass) {
        $failed += @{ id = $rule.id; title = $rule.title; severity = $rule.severity; expected = "$($rule.expected)"; actual = "$actual" }
    }
}

$total = @($baseline.rules).Count
$score = [int][math]::Round(100 * ($total - $failed.Count) / $total)
$failedIds = @($failed | ForEach-Object { $_.id })

# Compare with the previous check-in to find what changed.
if ($PreviousCheckins -is [string]) { $PreviousCheckins = $PreviousCheckins | ConvertFrom-Json }
$prev = @($PreviousCheckins)[0]
$prevFailed = if ($prev -and $prev.failedRules) { @("$($prev.failedRules)" -split ',') } else { @() }
$opened = @($failedIds | Where-Object { $_ -notin $prevFailed })
$resolved = @($prevFailed | Where-Object { $_ -notin $failedIds })

$now = (Get-Date).ToUniversalTime()
# Inverted timestamp, so the newest row for a device always sorts first.
$rowKey = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - $now.Ticks)
$device = "$($body.deviceName)"

# Record one drift event per rule that changed state.
$events = @()
foreach ($f in $failed | Where-Object { $_.id -in $opened }) {
    $events += @{
        PartitionKey = $device; RowKey = "$rowKey-$($f.id)"; event = 'opened'
        ruleId = $f.id; title = $f.title; severity = $f.severity
        expected = $f.expected; actual = $f.actual; detectedAtUtc = $now.ToString('o')
    }
}
foreach ($id in $resolved) {
    $rule = $baseline.rules | Where-Object { $_.id -eq $id } | Select-Object -First 1
    $events += @{
        PartitionKey = $device; RowKey = "$rowKey-$id"; event = 'resolved'
        ruleId = $id; title = "$($rule.title)"; severity = "$($rule.severity)"
        detectedAtUtc = $now.ToString('o')
    }
}
if ($events.Count -gt 0) { Push-OutputBinding -Name DriftTable -Value $events }

Push-OutputBinding -Name CheckinTable -Value @{
    PartitionKey  = $device
    RowKey        = $rowKey
    platform      = "$($body.platform)"
    agentVersion  = "$($body.agentVersion)"
    receivedAtUtc = $now.ToString('o')
    compliant     = ($failed.Count -eq 0)
    score         = $score
    failedRules   = ($failedIds -join ',')
    payload       = ($body | ConvertTo-Json -Depth 8 -Compress)
}

Send-Reply ([HttpStatusCode]::Accepted) @{
    received = $true; device = $device; score = $score
    failed = $failedIds; opened = $opened; resolved = $resolved
}
