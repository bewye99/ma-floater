[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'MA Floater'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$playerScript = Join-Path $projectRoot 'bin\MAFloater.ps1'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$expectedArguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $playerScript + '"'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -eq $task) {
    Write-Output 'The MA Floater autostart task is not installed.'
    return
}

$actions = @($task.Actions)
if ($actions.Count -ne 1 -or
    $actions[0].Execute -ne $windowsPowerShell -or
    $actions[0].Arguments -ne $expectedArguments -or
    $actions[0].WorkingDirectory -ne $projectRoot) {
    throw "The scheduled task named '$taskName' was not created by this MA Floater folder; refusing to remove it."
}

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Write-Output 'Removed the MA Floater autostart task.'
