[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'MA Floater'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$playerScript = Join-Path $projectRoot 'bin\MAFloater.ps1'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

if (-not (Test-Path -LiteralPath $playerScript)) {
    & (Join-Path $projectRoot 'Build.ps1')
}

$arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $playerScript + '"'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $existingAction = @($existing.Actions)[0]
    if ($existingAction.Execute -ne $windowsPowerShell -or $existingAction.Arguments -ne $arguments) {
        throw "A different scheduled task already uses the name '$taskName'."
    }
}
$action = New-ScheduledTaskAction -Execute $windowsPowerShell -Argument $arguments -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Starts MA Floater after this Windows user signs in.'
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

$registered = Get-ScheduledTask -TaskName $taskName
[pscustomobject]@{
    TaskName = $registered.TaskName
    State = $registered.State
    User = $registered.Principal.UserId
    LogonType = $registered.Principal.LogonType
}
