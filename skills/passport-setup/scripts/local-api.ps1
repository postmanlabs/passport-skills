param(
    [Parameter(Mandatory = $true)][string]$Method,
    [string]$Path,
    [string]$Body
)

$ErrorActionPreference = 'Stop'
$dir = if ($env:PASSPORT_DIR) { $env:PASSPORT_DIR } else { Join-Path $HOME '.passport' }
$session = Get-Content (Join-Path $dir 'passportrc') -Raw | ConvertFrom-Json
$token = $session.login._profiles[0].workos.accessToken
if (-not $token) { throw 'Passport login is missing.' }
$part = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
$part = $part.PadRight($part.Length + (4 - $part.Length % 4) % 4, '=')
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
if ($claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { throw 'Login expired; run passport auth status.' }
if (-not $claims.org_id) { throw 'Choose a Passport team before continuing.' }
if ($Method -eq 'user-id') { $claims.sub; return }
if ($Method -notin @('GET', 'POST', 'PUT', 'PATCH', 'DELETE') -or -not $Path.StartsWith('/')) { throw 'Invalid API method or path.' }
if (-not $env:PASSPORT_API) { throw 'PASSPORT_API is not set.' }
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$params = @{ Uri = $env:PASSPORT_API.TrimEnd('/') + $Path; Method = $Method; Headers = $headers; UseBasicParsing = $true }
if ($Body) {
    if ($Body.StartsWith('@')) { $Body = Get-Content -LiteralPath ($Body.Substring(1)) -Raw }
    $null = $Body | ConvertFrom-Json
    $params.Body = $Body
    $params.ContentType = 'application/json'
}
try {
    $response = Invoke-WebRequest @params
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'network error' }
    throw "Passport API $Method $Path failed: $code"
}
$result = if ($response.Content) { $response.Content | ConvertFrom-Json } else { '' }
@{ status = [int]$response.StatusCode; body = $result } | ConvertTo-Json -Depth 30
