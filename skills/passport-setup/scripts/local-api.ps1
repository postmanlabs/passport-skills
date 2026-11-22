param(
    [Parameter(Mandatory = $true)][string]$Method,
    [string]$Path,
    [string]$Body
)

$ErrorActionPreference = 'Stop'
$token = $env:PASSPORT_API_KEY
if (-not $token) { throw 'Set PASSPORT_API_KEY in the agent environment first.' }
if ($Method -notin @('GET', 'POST', 'PUT', 'PATCH', 'DELETE') -or -not $Path.StartsWith('/public/v1/')) { throw 'Only /public/v1/ API paths are allowed.' }
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
