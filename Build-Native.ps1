[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$solution = Join-Path $projectRoot 'MAFloater.Native.slnx'
$checks = Join-Path $projectRoot 'tests\MAFloater.FoundationChecks\MAFloater.FoundationChecks.csproj'
$app = Join-Path $projectRoot 'src\MAFloater.App\MAFloater.App.csproj'
$output = Join-Path $projectRoot 'artifacts\win-x64'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET 10 SDK is required. Install Microsoft.DotNet.SDK.10 first.'
}

$sdkVersion = (& dotnet --version).Trim()
if (-not $sdkVersion.StartsWith('10.')) {
    throw "The .NET 10 SDK is required; found $sdkVersion."
}

& dotnet restore $solution
if ($LASTEXITCODE -ne 0) { throw 'Native restore failed.' }

& dotnet build $solution --configuration Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }

& dotnet run --project $checks --configuration Release --no-build
if ($LASTEXITCODE -ne 0) { throw 'Native foundation checks failed.' }

& dotnet publish $app --configuration Release --runtime win-x64 --self-contained true `
    --property:PublishSingleFile=true --property:EnableCompressionInSingleFile=true `
    --output $output
if ($LASTEXITCODE -ne 0) { throw 'Native publish failed.' }

$executable = Join-Path $output 'MAFloater.exe'
if (-not (Test-Path -LiteralPath $executable)) {
    throw "Published executable is missing: $executable"
}

Write-Output "PASS: native build, foundation checks, and self-contained publish completed."
Write-Output "Published: $executable"
