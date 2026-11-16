[CmdletBinding()]
param(
    [switch]$SkipNativeBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectFile = Join-Path $projectRoot 'src\MAFloater.App\MAFloater.App.csproj'
$installerScript = Join-Path $projectRoot 'installer\MAFloater.iss'
$installerOutput = Join-Path $projectRoot 'artifacts\installer'

if (-not $SkipNativeBuild) {
    & (Join-Path $projectRoot 'Build-Native.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Native application build failed.' }
}

[xml]$project = Get-Content -LiteralPath $projectFile
$version = [string]$project.Project.PropertyGroup.Version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'The native application version is missing from MAFloater.App.csproj.'
}

$compilerCandidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$compiler = $compilerCandidates | Select-Object -First 1
if (-not $compiler) {
    throw 'Inno Setup 7 is required to build the installer. Download it from https://jrsoftware.org/isdl.php and rerun Build-Installer.ps1.'
}

New-Item -ItemType Directory -Path $installerOutput -Force | Out-Null
& $compiler "/DMyAppVersion=$version" "/O$installerOutput" $installerScript
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }

$installer = Join-Path $installerOutput "MAFloater-Setup-$version-x64.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Compiled installer is missing: $installer"
}

Write-Output 'PASS: native application and single-EXE installer build completed.'
Write-Output "Installer: $installer"
