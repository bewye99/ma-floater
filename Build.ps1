[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$windowsRuntime = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.Runtime.WindowsRuntime.dll'
$source = Join-Path $projectRoot 'src\MAFloater.ps1'
$outputDirectory = Join-Path $projectRoot 'bin'
$output = Join-Path $outputDirectory 'MAFloater.ps1'

$required = @(
    $windowsPowerShell,
    $windowsRuntime,
    $source
)

$missing = $required | Where-Object { -not (Test-Path -LiteralPath $_) }
if ($missing) {
    throw "Required Windows build components are missing:`n$($missing -join "`n")"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$tokens = $null
$syntaxErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$syntaxErrors) | Out-Null
if ($syntaxErrors) {
    $messages = $syntaxErrors | ForEach-Object { $_.Message }
    throw "MAFloater.ps1 contains syntax errors:`n$($messages -join "`n")"
}

Copy-Item -LiteralPath $source -Destination $output -Force
Write-Output "Prepared: $output"
