[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $projectRoot 'bin\MAFloater.ps1'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path -LiteralPath $script)) {
    & (Join-Path $projectRoot 'Build.ps1')
}

$arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -WindowStyle Hidden
