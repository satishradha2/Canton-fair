param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$keystorePath = Join-Path $root 'android\app\canton-fair-release.jks'
if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    throw 'Existing release keystore not found. Restore it; do not generate a replacement.'
}
$bytes = [IO.File]::ReadAllBytes($keystorePath)
if ($bytes.Length -eq 0) { throw 'The release keystore is empty.' }
$value = [Convert]::ToBase64String($bytes)
$decoded = [Convert]::FromBase64String($value)
if ($decoded.Length -ne $bytes.Length) { throw 'Base64 verification failed.' }
if ($ValidateOnly) {
    Write-Host 'Existing keystore Base64 encoding verified. Clipboard unchanged.'
} else {
    Set-Clipboard -Value $value
    Write-Host 'Copied ONLY the ANDROID_KEYSTORE_BASE64 value to your clipboard.'
    Write-Host 'Paste into that GitHub Actions secret and save. Do not paste it in chat.'
    Write-Host 'Clear the clipboard after saving: Set-Clipboard -Value ""'
}
