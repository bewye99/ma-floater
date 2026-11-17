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
Assert-True (
    $readme.Contains('Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force') -and
    $readme.Contains('no native executable or installer is included in the public release') -and
    $readme.IndexOf('## Install and run the public PowerShell release') -lt
        $readme.IndexOf('## Contributor and developer workflow')
) 'README must lead with the complete public PowerShell installation path and separate developer work.'
Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot 'LICENSE')) 'LICENSE is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot '.gitignore')) '.gitignore is missing.'

$signingPolicyPath = Join-Path $projectRoot 'CODE_SIGNING_POLICY.md'
$workflowPath = Join-Path $projectRoot '.github\workflows\windows-build.yml'
Assert-True (Test-Path -LiteralPath $signingPolicyPath) 'The code signing policy is missing.'
Assert-True (Test-Path -LiteralPath $workflowPath) 'The Windows build workflow is missing.'
$signingPolicyText = Get-Content -LiteralPath $signingPolicyPath -Raw
$workflowText = Get-Content -LiteralPath $workflowPath -Raw
Assert-True (
    $signingPolicyText.Contains('currently unsigned development artifacts') -and
    $signingPolicyText.Contains('SignPath Foundation has not accepted MA Floater yet') -and
    $signingPolicyText.Contains('generated uninstaller')
) 'The signing policy must state the actual unsigned status and complete signing scope.'
Assert-True (
    $workflowText.Contains('ma-floater-unsigned-${{ github.sha }}') -and
    $workflowText.Contains('retention-days: 7') -and
    -not $workflowText.Contains('release upload') -and
    -not $workflowText.Contains('gh release')
) 'Unsigned CI artifacts must remain short-lived inputs and must not be published as releases.'

$installerPath = Join-Path $projectRoot 'installer\MAFloater.iss'
$installerBuildPath = Join-Path $projectRoot 'Build-Installer.ps1'
Assert-True (Test-Path -LiteralPath $installerPath) 'The native installer definition is missing.'
Assert-True (Test-Path -LiteralPath $installerBuildPath) 'The native installer build script is missing.'
$installerText = Get-Content -LiteralPath $installerPath -Raw
$installerBuildText = Get-Content -LiteralPath $installerBuildPath -Raw
Assert-True (
    $installerText.Contains('PrivilegesRequired=lowest') -and
    $installerText.Contains('DefaultDirName={localappdata}\Programs\MA Floater')
) 'The native installer must remain a non-administrative per-user installation.'
Assert-True (
    $installerText.Contains('Source: "..\artifacts\win-x64\{#MyAppExeName}"') -and
    $installerText.Contains('Name: "{userprograms}\MA Floater"') -and
    $installerText.Contains('Flags: uninsdeletevalue')
) 'The native installer must package the verified app, create a Start menu entry, and own its startup value.'
Assert-True (
    $installerBuildText.Contains("Join-Path `$projectRoot 'Build-Native.ps1'") -and
    $installerBuildText.Contains('MAFloater-Setup-$version-x64.exe')
) 'The installer build must verify the native application and require the expected single-EXE output.'
Assert-True (
    -not $installerText.Contains('credential.dat') -and
    -not $installerText.Contains('connection.json')
) 'The installer must not bundle Music Assistant credentials or connection settings.'

$nativeWindowText = Get-Content -LiteralPath (Join-Path $projectRoot 'src\MAFloater.App\MainWindow.xaml.cs') -Raw
$nativeStartupText = Get-Content -LiteralPath (Join-Path $projectRoot 'src\MAFloater.App\StartupRegistration.cs') -Raw
Assert-True (
    $nativeWindowText.Contains('TimeSpan.FromSeconds(15)') -and
    $nativeWindowText.Contains('SetCompactMode(true)') -and
    $nativeWindowText.Contains('SetCompactMode(false)')
) 'The native compact-window timer and hover restoration are missing.'
Assert-True (
    $nativeStartupText.Contains('Registry.CurrentUser') -and
    $nativeStartupText.Contains('CurrentVersion\Run') -and
    $nativeStartupText.IndexOf('string.Equals(') -lt $nativeStartupText.IndexOf('key.DeleteValue(')
) 'Native startup removal must verify that the current executable owns the per-user startup value.'

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
$iconCount = [BitConverter]::ToUInt16($iconHeader, 4)
Assert-True ($iconCount -eq 4) 'The Windows icon must contain four image sizes.'
$iconSizes = for ($index = 0; $index -lt $iconCount; $index++) {
    $entryOffset = 6 + (16 * $index)
    $width = [int]$iconHeader[$entryOffset]
    $height = [int]$iconHeader[$entryOffset + 1]
    if ($width -eq 0) { $width = 256 }
    if ($height -eq 0) { $height = 256 }
    Assert-True ($width -eq $height) 'Every Windows icon frame must be square.'
    Assert-True ([BitConverter]::ToUInt16($iconHeader, $entryOffset + 6) -eq 32) `
        'Every Windows icon frame must use 32-bit color.'
    $width
}
Assert-True (
    (@($iconSizes) -join ',') -eq '16,32,48,256'
) 'The Windows icon must contain 16, 32, 48, and 256 pixel frames.'
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
Assert-True (
    $sourceText.Contains("[MAFloater.ShellIdentity]::SetCurrentProcessExplicitAppUserModelID('MAFloater.Desktop')") -and
    $sourceText.IndexOf("[MAFloater.ShellIdentity]::SetCurrentProcessExplicitAppUserModelID('MAFloater.Desktop')") -lt
        $sourceText.IndexOf('[xml]$xaml') -and
    $sourceText.Contains('$window.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon')
) 'The branded taskbar identity must be set before the WPF window is created.'
Assert-True (
    $sourceText.Contains('$taskbarIconHandle = [MAFloater.ShellIdentity]::LoadSharedIcon($iconPath, 40)') -and
    $sourceText.Contains('[MAFloater.ShellIdentity]::SetWindowIcons($windowHandle, $taskbarIconHandle)') -and
    $sourceText.Contains('SendMessage(windowHandle, SetIcon, new System.IntPtr(2), iconHandle);')
) 'The user-confirmed 40-pixel icon must be assigned to every Windows window-icon slot.'
$removeAutostart = Get-Content -LiteralPath (Join-Path $projectRoot 'Remove-Autostart.ps1') -Raw
$ownershipCheck = $removeAutostart.IndexOf('$actions[0].WorkingDirectory -ne $projectRoot')
$unregisterCall = $removeAutostart.IndexOf('Unregister-ScheduledTask')
Assert-True (
    $ownershipCheck -ge 0 -and $unregisterCall -gt $ownershipCheck
) 'Autostart removal must verify task ownership before unregistering it.'

$removeStartMenu = Get-Content -LiteralPath (Join-Path $projectRoot 'Remove-StartMenuShortcut.ps1') -Raw
$shortcutOwnershipCheck = $removeStartMenu.IndexOf('$matchesCurrent = $shortcut.TargetPath -eq $windowsPowerShell')
$shortcutRemoval = $removeStartMenu.IndexOf('Remove-Item -LiteralPath $shortcutPath')
Assert-True (
    $shortcutOwnershipCheck -ge 0 -and $shortcutRemoval -gt $shortcutOwnershipCheck
) 'Start menu removal must verify shortcut ownership before deleting it.'

$installStartMenu = Get-Content -LiteralPath (Join-Path $projectRoot 'Install-StartMenuShortcut.ps1') -Raw
Assert-True (
    $sourceText.Contains("SetCurrentProcessExplicitAppUserModelID('MAFloater.Desktop')") -and
    $installStartMenu.Contains("`$appUserModelId = 'MAFloater.Desktop'") -and
    $installStartMenu.Contains("SetAppUserModelId(`$shortcutPath, `$appUserModelId)") -and
    $installStartMenu.Contains("ExtendedProperty('System.AppUserModel.ID')")
) 'The process and Start menu shortcut must use the same verified Windows app identity.'
Assert-True (
    $installStartMenu.Contains('$shortcut.TargetPath = $windowsPowerShell') -and
    $installStartMenu.Contains('-WindowStyle Hidden') -and
    $installStartMenu.Contains('-ExecutionPolicy Bypass') -and
    -not $installStartMenu.Contains('$shortcut.TargetPath = $windowsScriptHost')
) 'The Start menu shortcut must launch hidden Windows PowerShell directly without requiring VBScript.'

$connectionSetup = Get-Content -LiteralPath (Join-Path $projectRoot 'Set-MusicAssistantConnection.ps1') -Raw
$loginCall = $connectionSetup.IndexOf('/auth/login')
$guestCheck = $connectionSetup.IndexOf("[string]`$login.user.role -ne 'guest'")
$credentialWrite = $connectionSetup.IndexOf('[IO.File]::WriteAllBytes($credentialPath, $protectedBytes)')
$providerField = $connectionSetup.IndexOf("provider_id = 'builtin'")
$credentialsBlock = $connectionSetup.IndexOf('credentials = @{', $providerField)
$usernameField = $connectionSetup.IndexOf('username = $Username.Trim()', $credentialsBlock)
$passwordField = $connectionSetup.IndexOf('password = $plainPassword', $usernameField)
$deviceNameField = $connectionSetup.IndexOf("device_name = 'MA Floater connection setup'", $passwordField)
Assert-True (
    $loginCall -ge 0 -and $guestCheck -gt $loginCall -and $credentialWrite -gt $guestCheck -and
    $providerField -ge 0 -and $credentialsBlock -gt $providerField -and
    $usernameField -gt $credentialsBlock -and $passwordField -gt $usernameField -and
    $deviceNameField -gt $passwordField -and
    $connectionSetup.Contains('ConvertTo-Json -Depth 6 -Compress') -and
    $connectionSetup.Contains('If Ctrl+V does not work, use right-click or Shift+Insert to paste.') -and
    $connectionSetup.Contains('if ($login.token)') -and
    $connectionSetup.Contains("command = 'auth/logout'") -and
    $connectionSetup.Contains("+ '/api'")
) 'Connection setup must validate the login and Guest role before saving credentials and explain masked paste behavior.'

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
