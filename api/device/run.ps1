using namespace System.Net
param($Request, $TriggerMetadata, $Latest, $DriftRows)

function Send-Json($Status, $Object) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $Status; ContentType = 'application/json'; Body = ($Object | ConvertTo-Json -Depth 6)
    })
}

if ($Latest -is [string]) { $Latest = $Latest | ConvertFrom-Json }
if ($DriftRows -is [string]) { $DriftRows = $DriftRows | ConvertFrom-Json }

$row = @($Latest) | Where-Object { $_ } | Select-Object -First 1
if (-not $row) {
    Send-Json ([HttpStatusCode]::NotFound) @{ error = 'unknown device' }
    return
}

# Rebuild pass/fail per rule from the stored list of failed rule ids.
$failedIds = if ($row.failedRules) { @("$($row.failedRules)" -split ',') } else { @() }
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Join-Path $env:HOME 'site\wwwroot' }
$rules = @()
if ($row.platform -in @('windows', 'macos')) {
    $baselinePath = Join-Path $root "baselines\$($row.platform).json"
    if (Test-Path $baselinePath) {
        $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
        $rules = @($baseline.rules | ForEach-Object {
            @{ id = $_.id; title = $_.title; severity = $_.severity; pass = ($_.id -notin $failedIds) }
        })
    }
}

$drift = @(@($DriftRows) | Where-Object { $_ } | ForEach-Object {
    @{ ruleId = $_.ruleId; title = $_.title; severity = $_.severity; event = $_.event
       expected = $_.expected; actual = $_.actual; at = $_.detectedAtUtc }
})

# Only summary fields are returned; the raw payload is never exposed.
Send-Json ([HttpStatusCode]::OK) @{
    name = $row.PartitionKey; platform = $row.platform; score = $row.score
    compliant = $row.compliant; lastSeenUtc = $row.receivedAtUtc
    rules = $rules; drift = $drift
}
