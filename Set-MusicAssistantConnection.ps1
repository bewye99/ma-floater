[CmdletBinding()]
param(
    [string]$ServerUrl,
    [string]$PreferredQueue,
    [string]$Username
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http
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

Write-Host 'Enter the password for the dedicated Guest Music Assistant account.'
Write-Host 'No characters will appear. If Ctrl+V does not work, use right-click or Shift+Insert to paste.'
$securePassword = Read-Host -AsSecureString 'Password'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plainPassword = $null
$plainBytes = $null
$httpClient = $null
$accessToken = $null
$response = $null
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($plainPassword)) { throw 'No password was entered.' }

    $serverBaseUrl = $parsedServerUrl.AbsoluteUri.TrimEnd('/')
    $loginBody = @{
        provider_id = 'builtin'
        credentials = @{
            username = $Username.Trim()
            password = $plainPassword
        }
        device_name = 'MA Floater connection setup'
    } | ConvertTo-Json -Depth 6 -Compress
    $httpClient = [Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds(15)
    $loginContent = [Net.Http.StringContent]::new($loginBody, [Text.Encoding]::UTF8, 'application/json')
    try {
        $response = $httpClient.PostAsync("$serverBaseUrl/auth/login", $loginContent).GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }
    catch {
        throw "Could not connect to Music Assistant at $serverBaseUrl. $($_.Exception.Message)"
    }
    finally {
        $loginContent.Dispose()
    }
    if (-not $response.IsSuccessStatusCode) {
        $safeMessage = $null
        try { $safeMessage = [string](($responseText | ConvertFrom-Json).error) } catch {}
        if ([string]::IsNullOrWhiteSpace($safeMessage)) {
            $safeMessage = "HTTP $([int]$response.StatusCode)"
        }
        throw "Music Assistant rejected the connection: $safeMessage. Check the server URL, username, and password."
    }

    $login = $responseText | ConvertFrom-Json
    $accessToken = if ($login.token) { [string]$login.token } else { [string]$login.access_token }
    if (-not $login.success -or [string]::IsNullOrWhiteSpace($accessToken)) {
        $detail = if ($login.error) { [string]$login.error } else { 'Music Assistant rejected the sign-in.' }
        throw $detail
    }
    if ([string]$login.user.role -ne 'guest') {
        throw 'The configured Music Assistant account is not a Guest account. Change its role to Guest before saving it in MA Floater.'
    }

    $plainBytes = [Text.Encoding]::UTF8.GetBytes($plainPassword)
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
        $plainBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes($credentialPath, $protectedBytes)
    @{
        server_url = $serverBaseUrl
        preferred_queue = $PreferredQueue
        username = $Username.Trim()
    } | ConvertTo-Json | Set-Content -LiteralPath $connectionPath -Encoding UTF8
}
finally {
    if ($null -ne $httpClient -and -not [string]::IsNullOrWhiteSpace($accessToken)) {
        $logoutContent = $null
        try {
            $httpClient.DefaultRequestHeaders.Authorization =
                [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $accessToken)
            $logoutBody = @{
                command = 'auth/logout'
                message_id = [guid]::NewGuid().ToString('N')
                args = @{}
            } | ConvertTo-Json -Compress
            $logoutContent = [Net.Http.StringContent]::new(
                $logoutBody, [Text.Encoding]::UTF8, 'application/json'
            )
            $logoutResponse = $httpClient.PostAsync(
                ($parsedServerUrl.AbsoluteUri.TrimEnd('/') + '/api'),
                $logoutContent
            ).GetAwaiter().GetResult()
            $logoutResponse.Dispose()
        }
        catch {}
        finally {
            if ($null -ne $logoutContent) { $logoutContent.Dispose() }
        }
    }
    if ($null -ne $response) { $response.Dispose() }
    if ($null -ne $httpClient) { $httpClient.Dispose() }
    if ($null -ne $plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    $plainPassword = $null
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host "Verified the Guest account and saved the MA Floater connection under $settingsDirectory for the current Windows user."
