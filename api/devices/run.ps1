using namespace System.Net
param($Request, $TriggerMetadata, $DeviceList)

if ($DeviceList -is [string]) { $DeviceList = $DeviceList | ConvertFrom-Json }
$devices = @(@($DeviceList) | Where-Object { $_ } | ForEach-Object {
    @{ name = $_.RowKey; platform = $_.platform; firstSeenUtc = $_.firstSeenUtc }
})

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]::OK
    ContentType = 'application/json'
    Body        = (@{ devices = $devices } | ConvertTo-Json -Depth 5)
})
