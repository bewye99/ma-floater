[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $projectRoot 'src\MAFloater.ps1'
$built = Join-Path $projectRoot 'bin\MAFloater.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$scriptFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.ps1')
foreach ($file in $scriptFiles) {
    $tokens = $null
    $syntaxErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$syntaxErrors
    ) | Out-Null
    Assert-True (-not $syntaxErrors) "PowerShell syntax failed: $($file.FullName)"
}

Assert-True (Test-Path -LiteralPath $source) 'The MA Floater source file is missing.'
Assert-True (Test-Path -LiteralPath $built) 'Run Build.ps1 before Test.ps1.'
Assert-True (
    (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -eq
    (Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash
) 'The runnable bin copy does not match the source. Run Build.ps1.'

$publicFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
        Where-Object { $_.Name -ne 'Test.ps1' -and $_.Extension -in @('.ps1', '.md') }
)
$publicText = ($publicFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$forbidden = @(
    'ma-mini-player',
    'Music Assistant Mini Player',
    'MusicAssistantMiniPlayer',
    'C:\Users\'
)
foreach ($value in $forbidden) {
    Assert-True (-not $publicText.Contains($value)) "Publication check found a legacy or personal value: $value"
}

$readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
Assert-True ($readme.Contains('# MA Floater')) 'README branding is missing.'
Assert-True ($readme.Contains('unofficial')) 'README must identify the project as unofficial.'
Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot 'LICENSE')) 'LICENSE is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot '.gitignore')) '.gitignore is missing.'
$iconPath = Join-Path $projectRoot 'assets\ma-floater.ico'
$iconSourcePath = Join-Path $projectRoot 'assets\ma-floater.png'
Assert-True (Test-Path -LiteralPath $iconPath) 'The Windows icon is missing.'
Assert-True (Test-Path -LiteralPath $iconSourcePath) 'The transparent icon source is missing.'
$iconHeader = [IO.File]::ReadAllBytes($iconPath)
Assert-True (
    $iconHeader.Length -gt 6 -and
    $iconHeader[0] -eq 0 -and $iconHeader[1] -eq 0 -and
    $iconHeader[2] -eq 1 -and $iconHeader[3] -eq 0
) 'The Windows icon header is invalid.'
$runtimeArtifacts = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
        Where-Object { $_.Name -in @('connection.json', 'credential.dat', 'settings.txt') }
)
Assert-True ($runtimeArtifacts.Count -eq 0) 'A runtime credential or settings file is inside the project.'

$sourceText = Get-Content -LiteralPath $source -Raw
Assert-True (
    $sourceText.Contains('$script:artworkHttpClient.GetByteArrayAsync') -and
    -not $sourceText.Contains('$script:httpClient.GetByteArrayAsync')
) 'Artwork downloads must use the unauthenticated artwork client.'
Assert-True (
    $sourceText.Contains('$script:artworkHttpClient.DefaultRequestHeaders.Authorization')
) 'The artwork authorization guard is missing.'

$removeAutostart = Get-Content -LiteralPath (Join-Path $projectRoot 'Remove-Autostart.ps1') -Raw
$ownershipCheck = $removeAutostart.IndexOf('$actions[0].WorkingDirectory -ne $projectRoot')
$unregisterCall = $removeAutostart.IndexOf('Unregister-ScheduledTask')
Assert-True (
    $ownershipCheck -ge 0 -and $unregisterCall -gt $ownershipCheck
) 'Autostart removal must verify task ownership before unregistering it.'

$sourceAst = [Management.Automation.Language.Parser]::ParseFile(
    $source, [ref]$null, [ref]$null
)
$selectionFunction = $sourceAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Select-CurrentQueue'
}, $true)
Assert-True ($null -ne $selectionFunction) 'Select-CurrentQueue was not found.'
Invoke-Expression $selectionFunction.Extent.Text

function New-TestQueue {
    param([string]$Id, [string]$Name, [string]$State, [bool]$HasItem = $true)
    [pscustomobject]@{
        queue_id = $Id
        display_name = $Name
        state = $State
        available = $true
        current_item = if ($HasItem) { [pscustomobject]@{ name = 'Track' } } else { $null }
    }
}

$script:preferredQueue = 'Preferred'
$script:currentQueueId = $null
$selected = Select-CurrentQueue @(
    (New-TestQueue 'preferred' 'Preferred' 'idle' $false),
    (New-TestQueue 'active' 'Active' 'playing')
)
Assert-True ($selected.queue_id -eq 'active') 'The active queue was not selected.'

$script:currentQueueId = 'active'
$selected = Select-CurrentQueue @(
    (New-TestQueue 'active' 'Active' 'paused'),
    (New-TestQueue 'new' 'New' 'playing')
)
Assert-True ($selected.queue_id -eq 'new') 'A newly playing queue did not replace a paused queue.'

$script:currentQueueId = $null
$selected = Select-CurrentQueue @(
    (New-TestQueue 'preferred' 'Preferred' 'idle'),
    (New-TestQueue 'stale' 'Stale' 'idle')
)
Assert-True ($selected.queue_id -eq 'preferred') 'The preferred fallback queue was not selected.'

Write-Output "PASS: $($scriptFiles.Count) PowerShell files parsed; build, publication, and queue-selection checks passed."
