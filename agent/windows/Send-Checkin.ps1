param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$ApiKey
)
# Several checks need administrator rights. Refuse to send misleading data without them.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error 'Send-Checkin must run from an administrator PowerShell window.'
    exit 1
}
$json = & "$PSScriptRoot\Collect-Compliance.ps1" | Out-String
Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $json -ContentType 'application/json' -Headers @{ 'x-functions-key' = $ApiKey }
