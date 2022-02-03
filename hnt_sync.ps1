<#

.SYNOPSIS
This script checks the sync status of your Bobcat Miner 300 and invokes fastsync if it is out of sync.
This can resolve the symptom of a Bobcat shown as offline in the Helium Explorer.

.PARAMETER bobcat_ip
The private IP Address of your Bobcat miner on your network.

.PARAMETER bobcat_location
The geographic location of your Bobcat Miner 300. Useful to clarify the miner which has the issue when alerting on multiple miners in PagerDuty.

.PARAMETER pd_enabled
A bolean to enable PagerDuty alerting.

.PARAMETER pd_routing_key
Your API key for your PagerDuty integration.

.NOTES
Invoke this script from crontab on Linux or Task Schduler on Windows to run on a schedule.

.EXAMPLE
pwsh -c "./hnt_sync.ps1 -bobcat_ip 10.1.0.100"

.EXAMPLE
./hnt_sync.ps1 -bobcat_ip 10.1.0.100 -bobcat_location "nyc" -pd_enabled 1 -pd_routing_key xxxxxxxxxxxxxxxxxxxxxxxxx

.EXAMPLE
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-c $env:HOME\Documents\hnt_monitoring\hnt_sync.ps1 -bobcat_ip 10.1.0.100 -bobcat_location "nyc" -pd_enabled 1 -pd_routing_key xxxxxxxxxxxxxxxxxxxxxxxxx'
$trigger =  New-ScheduledTaskTrigger -Daily -At 8pm
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "hnt_monitor" -Description "Daily run to monitor Bobcat miner sync status"

#>

#Requires -PSEdition Core
#Requires -Modules PowerShellGet

[CmdletBinding()]
Param (
    [string]    $bobcat_ip,
    [string]    $bobcat_location,
    [bool]      $pd_enabled,
    [string]    $pd_routing_key
)

$sync_time = get-date

if ($IsLinux) {
    Write-Debug -Message "This script is running on Linux"
    $hnt_sync = curl -H "Content-Type: application/json" --request GET http://$bobcat_ip/status.json
} elseif ($IsWindows) {
    Write-Debug -Message "This script is running on Windows"
    $hnt_sync = Invoke-WebRequest -Uri http://$bobcat_ip/status.json -UseBasicParsing -OutFile $null
}

$sync_stats = $hnt_sync | ConvertFrom-Json

$gap = $sync_stats.gap

if (!(Test-Path $env:HOME/hnt_stats/)) {
    New-Item -ItemType Directory -Force -Path $env:HOME/hnt_stats/
}

$Logfile = "$env:HOME/hnt_stats/hnt_sync.log"
Add-Content $Logfile -value $sync_time
Add-Content $Logfile -value $sync_stats

function Import-Pd {
    if (Get-Module -ListAvailable -Name PagerDutyEventV2) {
        Write-Verbose -Message "PagerDutyEventV2 Powershell module found. Attempting module import..." -Verbose
        Import-Module -Name PagerDutyEventV2 -Force
    } else {
        Write-Verbose -Message "PagerDutyEventV2 Powershell module not found. Attempting module install and import..." -Verbose
        Install-Module -Name PagerDutyEventV2 -Scope CurrentUser -Force
        Import-Module -Name PagerDutyEventV2 -Force
    }
}

function Write-Hntsuccess {
    Write-Verbose -Message "Bobcat is in sync. No action required." -Verbose
    Add-Content $Logfile -value "Bobcat is in sync. No action required."
}

if ($gap -gt 0) {
    Write-Verbose -Message "Bobcat is out of sync. Sync gap currently: $($sync_stats.gap) Sending PD alert..." -Verbose
    Add-Content $Logfile -value "Bobcat is out of sync. Sync gap currently: $($sync_stats.gap) Sending PD alert..."
    if ($pd_enabled) {
        Write-Verbose -Message "PagerDuty alerting enabled. Attempting to create PD incident." -Verbose
        Import-Pd

        # if (Get-Module -ListAvailable -Name PagerDutyEventV2) {
        #     Write-Verbose -Message "PagerDutyEventV2 Powershell module found. Attempting module import..." -Verbose
        #     Import-Module -Name PagerDutyEventV2 -Force
        # } else {
        #     Write-Verbose -Message "PagerDutyEventV2 Powershell module not found. Attempting module install and import..." -Verbose
        #     Install-Module -Name PagerDutyEventV2 -Scope CurrentUser -Force
        #     Import-Module -Name PagerDutyEventV2 -Force
        # }

        New-PagerDutyAlert -RoutingKey $pd_routing_key `
            -Summary hntAlert `
            -Severity Critical `
            -Source testSource `
            -CustomDetails @{purpose="sync status";region="$bobcat_location"} `
            -DeduplicationKey 'testKey' `
            -Component 'testComponent' `
            -Group 'testGroup' `
            -Class 'testClass'
    } else {
        Write-Verbose -Message "PagerDuty alerting disabled. Skipping PD incident creation." -Verbose
    }
    if ($gap -gt 400) {
        if ($IsLinux) {
            Write-Debug -Message "Fast sync required - Running Linux native curl command"
            $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
            $post_error = "curl: (56) Recv failure: Connection reset by peer"
            $post_success = "Syncing your miner, please leave your power on."
            if ($post_result -eq $post_success) {
                Write-Verbose -Message "Fastsync successful. Bobcat is now in sync." -Verbose
                Add-Content $Logfile -value "Fastsync successful. Bobcat is now in sync."
            } elseif ($post_result -eq $post_error) {
            while ($post_result -eq $post_error) {
                Start-Sleep 120
                $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
            }
            } elseif (($post_result -ne $post_success) -or ($post_result -eq $post_error)) {
                Write-Verbose -Message "Another type error exists." -Verbose
                Add-Content $Logfile -value "Another type error exists. Post result: $post_result"
            }
        } elseif ($IsWindows) {
            Write-Debug -Message "Fast sync required - Running Windows PowerShell curl command"
            $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
            $post_error = "curl: (56) Recv failure: Connection reset by peer"
            $post_success = "Syncing your miner, please leave your power on."
            if ($post_result -eq $post_success) {
                Write-Verbose -Message "Fastsync successful. Bobcat is now in sync." -Verbose
                Add-Content $Logfile -value "Fastsync successful. Bobcat is now in sync."
            } elseif ($post_result -eq $post_error) {
            while ($post_result -eq $post_error) {
                Start-Sleep 120
                $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
            }
            } elseif (($post_result -ne $post_success) -or ($post_result -eq $post_error)) {
                Write-Verbose -Message "Another type error exists." -Verbose
                Add-Content $Logfile -value "Another type error exists. Post result: $post_result"
            }
        }
    }
} else {
    Write-Hntsuccess
}
