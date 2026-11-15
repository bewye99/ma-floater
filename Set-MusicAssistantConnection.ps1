[CmdletBinding()]
param(
    [string]$ServerUrl,
    [string]$PreferredQueue,
    [string]$Username
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$settingsDirectory = Join-Path $env:LOCALAPPDATA 'MAFloater'
$connectionPath = Join-Path $settingsDirectory 'connection.json'
$credentialPath = Join-Path $settingsDirectory 'credential.dat'

if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    $ServerUrl = Read-Host 'Music Assistant server URL (for example, http://192.168.1.10:8095)'
}
if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Read-Host 'Dedicated Music Assistant Guest username'
}
if ($null -eq $PreferredQueue) {
    $PreferredQueue = Read-Host 'Preferred fallback queue name (optional; press Enter for none)'
}

$parsedServerUrl = $null
if (-not [uri]::TryCreate($ServerUrl, [UriKind]::Absolute, [ref]$parsedServerUrl) -or
    $parsedServerUrl.Scheme -notin @('http', 'https') -or
    [string]::IsNullOrWhiteSpace($parsedServerUrl.Host)) {
    throw 'ServerUrl must be an absolute HTTP or HTTPS URL.'
}
if ([string]::IsNullOrWhiteSpace($Username)) {
    throw 'A dedicated Music Assistant Guest username is required.'
}

Write-Host 'Enter the password for the dedicated Guest Music Assistant account. It will not be displayed.'
$securePassword = Read-Host -AsSecureString 'Password'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plainPassword = $null
$plainBytes = $null
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($plainPassword)) { throw 'No password was entered.' }
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($plainPassword)
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
        $plainBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes($credentialPath, $protectedBytes)
    @{
        server_url = $parsedServerUrl.AbsoluteUri.TrimEnd('/')
        preferred_queue = $PreferredQueue
        username = $Username.Trim()
    } | ConvertTo-Json | Set-Content -LiteralPath $connectionPath -Encoding UTF8
}
finally {
    if ($null -ne $plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    $plainPassword = $null
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host "MA Floater connection saved under $settingsDirectory for the current Windows user."
