using namespace System.Net
param($Request, $TriggerMetadata)

$body = $Request.Body

# Reject anything that is not a valid check-in.
if (-not $body -or -not $body.deviceName -or -not $body.checks) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'deviceName and checks are required'
    })
    return
}

$now = (Get-Date).ToUniversalTime()
# Inverted timestamp, so the newest check-in for a device always sorts first.
$rowKey = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - $now.Ticks)

Push-OutputBinding -Name CheckinTable -Value @{
    PartitionKey  = "$($body.deviceName)"
    RowKey        = $rowKey
    platform      = "$($body.platform)"
    agentVersion  = "$($body.agentVersion)"
    receivedAtUtc = $now.ToString('o')
    payload       = ($body | ConvertTo-Json -Depth 8 -Compress)
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::Accepted
    Body       = @{ received = $true; device = "$($body.deviceName)"; rowKey = $rowKey }
})
