#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Runs one check. If it fails, the error is recorded instead of crashing the agent.
function Get-Check {
    param([string]$Name, [scriptblock]$Script)
    try {
        [ordered]@{ name = $Name; status = 'ok'; value = (& $Script) }
    }
    catch {
        [ordered]@{ name = $Name; status = 'error'; value = $null; error = $_.Exception.Message }
    }
}

$checks = @(
    Get-Check 'firewall' {
        $r = [ordered]@{}
        foreach ($p in Get-NetFirewallProfile -ErrorAction Stop) { $r[$p.Name.ToLower()] = ($p.Enabled -eq 'True') }
        $r
    }
    Get-Check 'diskEncryption' {
        $v = Get-BitLockerVolume -ErrorAction Stop -MountPoint $env:SystemDrive
        [ordered]@{ protectionStatus = "$($v.ProtectionStatus)"; volumeStatus = "$($v.VolumeStatus)" }
    }
    Get-Check 'defender' {
        $s = Get-MpComputerStatus -ErrorAction Stop
        [ordered]@{
            realTimeProtection = $s.RealTimeProtectionEnabled
            antivirusEnabled   = $s.AntivirusEnabled
            signatureAgeDays   = $s.AntivirusSignatureAge
        }
    }
    Get-Check 'pendingUpdates' {
        $session = New-Object -ComObject Microsoft.Update.Session
        $result  = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
        [ordered]@{
            count          = $result.Updates.Count
            rebootRequired = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        }
    }
    Get-Check 'localAdmins' {
        $m = @(Get-LocalGroupMember -ErrorAction Stop -Group 'Administrators' | ForEach-Object { $_.Name })
        [ordered]@{ count = $m.Count; members = $m }
    }
    Get-Check 'screenLock' {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $t = (Get-ItemProperty -Path $key -Name InactivityTimeoutSecs -ErrorAction SilentlyContinue).InactivityTimeoutSecs
        [ordered]@{ configured = ($null -ne $t); inactivityTimeoutSecs = $t }
    }
)

$os = Get-CimInstance Win32_OperatingSystem

[ordered]@{
    schemaVersion  = 1
    agentVersion   = '0.1.0'
    deviceName     = $env:COMPUTERNAME
    platform       = 'windows'
    osCaption      = $os.Caption
    osVersion      = $os.Version
    collectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    checks         = $checks
} | ConvertTo-Json -Depth 6
