param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9/_-]*$')]
    [string]$VaultKey
)

$ErrorActionPreference = 'Stop'
$tokenPath = '/tmp/pp-local/vault-token'
if (-not (Test-Path $tokenPath)) { throw 'Vault token file is missing.' }
$secure = Read-Host 'Secret value' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ([string]::IsNullOrEmpty($value)) { throw 'Empty value; nothing stored.' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = 'docker'
    $start.Arguments = "exec -i -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN pp-vault-dev vault kv put secret/$VaultKey value=-"
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['VAULT_TOKEN'] = [IO.File]::ReadAllText($tokenPath).Trim()
    $process = [Diagnostics.Process]::Start($start)
    $process.StandardInput.Write($value)
    $process.StandardInput.Close()
    $out = $process.StandardOutput.ReadToEnd()
    $err = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Vault write failed: $err" }
    Write-Output 'stored'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $value = $null
    $secure.Dispose()
}
