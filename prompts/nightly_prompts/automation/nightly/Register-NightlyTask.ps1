#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [string]$TaskName='ai-fosql-nightly'
)
. "$PSScriptRoot\Common.ps1"
$cfg = Get-NightlyConfig $ConfigPath
if (!$cfg.runtimeApproved) { throw 'Finish the manual smoke test and set runtimeApproved=true before scheduling.' }
$configFull = (Resolve-Path -LiteralPath $ConfigPath).Path
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { throw "Scheduled task exists: $TaskName. No overwrite." }
$runner = Join-Path $PSScriptRoot 'Invoke-Nightly.ps1'
$command = "& '" + $runner.Replace("'","''") + "' -ConfigPath '" + $configFull.Replace("'","''") + "'"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$action = New-ScheduledTaskAction -Execute $shell -Argument "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded" -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.Add([TimeSpan]::Parse($cfg.startTimeLocal)))
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes ($cfg.maxRunMinutes + 15))
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
if ($PSCmdlet.ShouldProcess($TaskName, 'Register daily task for the currently logged-on user')) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Write-Host "Registered $TaskName at $($cfg.startTimeLocal), MACHINE local time."
    Write-Host 'Keep this Windows user logged on. Locking/disconnecting RDP is not logging off. No wake-from-sleep or missed-run catch-up is enabled.'
}
