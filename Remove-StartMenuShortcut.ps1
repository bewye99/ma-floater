[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shortcutName = 'MA Floater.lnk'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$playerScript = Join-Path $projectRoot 'bin\MAFloater.ps1'
$launcherScript = Join-Path $projectRoot 'Start-MAFloater.vbs'
$iconPath = Join-Path $projectRoot 'assets\ma-floater.ico'
$windowsScriptHost = Join-Path $env:WINDIR 'System32\wscript.exe'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$expectedArguments = '"' + $launcherScript + '"'
$legacyArguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $playerScript + '"'
$expectedIconLocation = $iconPath + ',0'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) $shortcutName

if (-not (Test-Path -LiteralPath $shortcutPath)) {
    Write-Output 'The MA Floater Start menu shortcut is not installed.'
    return
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$matchesCurrent = $shortcut.TargetPath -eq $windowsScriptHost -and
    $shortcut.Arguments -eq $expectedArguments
$matchesLegacy = $shortcut.TargetPath -eq $windowsPowerShell -and
    $shortcut.Arguments -eq $legacyArguments
if ((-not $matchesCurrent -and -not $matchesLegacy) -or
    $shortcut.WorkingDirectory -ne $projectRoot -or
    $shortcut.IconLocation -ne $expectedIconLocation) {
    throw "The shortcut named '$shortcutName' was not created by this MA Floater folder; refusing to remove it."
}

Remove-Item -LiteralPath $shortcutPath
Write-Output 'Removed the MA Floater Start menu shortcut.'
