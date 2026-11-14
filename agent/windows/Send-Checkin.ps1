param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$ApiKey
)
$json = & "$PSScriptRoot\Collect-Compliance.ps1" | Out-String
Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $json -ContentType 'application/json' -Headers @{ 'x-functions-key' = $ApiKey }
