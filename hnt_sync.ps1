<#

.SYNOPSIS
This script checks the sync status of your Bobcat and fastsyncs if it is out of sync.

.PARAMETER bobcat_ip
The private IP Address of your Bobcat miner on your network.

.PARAMETER bobcat_location
The location of your Bobcat miner.

.PARAMETER pd_enabled
A bolean to enable PagerDuty alering.

.PARAMETER pd_routing_key
Your API key for your PagerDuty integration.

.NOTES
Invoke this script from crontab on Linux or Task Schduler on Windows to run on a schedule.

.EXAMPLE
pwsh -c "./hnt_sync.ps1 -bobcat_ip 10.1.0.100"

.EXAMPLE
./hnt_sync.ps1 -bobcat_ip 10.1.0.100 -bobcat_locattion "nyc" -pd_enabled 1 -$pd_routing_key xxxxxxxxxxxxxxxxxxxxxxxxxx

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

if ($IsLinux) {
    write-host -Message "This script is running on Linux" -Verbose
    $sync_time = get-date 
    $hnt_sync = curl -H "Content-Type: application/json" --request GET http://$bobcat_ip/status.json
} else {
    write-host -Message "This script is running on Windows" -Verbose
    $hnt_sync = Invoke-WebRequest -Uri http://$bobcat_ip/status.json -UseBasicParsing -OutFile $null
}

$sync_stats = $hnt_sync | ConvertFrom-Json

$sync_stats.gap

if (!(Test-Path $env:HOME/hnt_stats/)){
    New-Item -ItemType Directory -Force -Path $env:HOME/hnt_stats/
}

$Logfile = "$env:HOME/hnt_stats/hnt_sync.log"
Add-content $Logfile -value $sync_time
Add-content $Logfile -value $sync_stats

# function Import-Pd {
#     if (Get-Module -ListAvailable -Name PagerDutyEventV2) {
#         Write-Verbose -Message "PagerDutyEventV2 Powershell module found. Attempting module import..." -Verbose
#         Import-Module -Name PagerDutyEventV2 -Force
#     } else {
#         Write-Verbose -Message "PagerDutyEventV2 Powershell module not found. Attempting module install and import..." -Verbose
#         Install-Module -Name PagerDutyEventV2 -Force
#         Import-Module -Name PagerDutyEventV2 -Force
#     }
# }

if ($sync_stats.gap -gt 0) {
    Write-Verbose -Message "Bobcat is out of sync. Sync gap currently: $($sync_stats.gap) Sending PD alert and attempting fastsync..." -Verbose
    Add-content $Logfile -value "Bobcat is out of sync. Sync gap currently: $($sync_stats.gap) Sending PD alert and attempting fastsync..."
    if ($pd_enabled) {
        Write-Verbose -Message "PagerDuty alerting enabled. Attempting to create PD incident." -Verbose
        if (Get-Module -ListAvailable -Name PagerDutyEventV2) {
            Write-Verbose -Message "PagerDutyEventV2 Powershell module found. Attempting module import..." -Verbose
            Import-Module -Name PagerDutyEventV2 -Force
        } else {
            Write-Verbose -Message "PagerDutyEventV2 Powershell module not found. Attempting module install and import..." -Verbose
            Install-Module -Name PagerDutyEventV2 -Force
            Import-Module -Name PagerDutyEventV2 -Force
        }
        New-PagerDutyAlert -RoutingKey $pd_routing_key -Summary hntAlert -Severity Critical -Source testSource -CustomDetails @{purpose="sync status";region="$bobcat_location"} -DeduplicationKey 'testKey' -Component 'testComponent' -Group 'testGroup' -Class 'testClass'
    } else {
        Write-Verbose -Message "PagerDuty alerting disabled. Skipping PD incident creation." -Verbose
    }
    # $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
    # $post_error = "curl: (56) Recv failure: Connection reset by peer"
    # $post_success = "Syncing your miner, please leave your power on."
    # if ($post_result -eq $post_success) {
    #     Write-Verbose -Message "Fastsync successful. Bobcat is now in sync." -Verbose
    #     Add-content $Logfile -value "Fastsync successful. Bobcat is now in sync."
    # }
    # if ($post_result -eq $post_error) {
    #   while ($post_result -eq $post_error) {
    #       Start-Sleep 60
    #       $post_result = curl --user bobcat:miner --request POST  http://$bobcat_ip/admin/fastsync
    #   }
    # }
    # if (($post_result -ne $post_success) -or ($post_result -eq $post_error)) {
    #     Write-Verbose -Message "Another type error exists." -Verbose
    #     Add-content $Logfile -value "Another type error exists. Post result: $post_result"
    # }
} else {
    Write-Verbose -Message "Bobcat is in sync. No action required." -Verbose
}

# function Get-PSVersion {
#     $PSVersionTable.PSVersion
#     Write-Verbose -Message "Bobcat is in sync. No action required." -Verbose
# }

# Get-PSVersion