param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS')]
    [string]$Name,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($relative in @('android\app\canton-fair-release.jks', 'android\key.properties')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw 'Existing release signing files are required. This helper must not create a replacement key.'
    }
}
# Java reads the properties correctly and exports only after private-key validation.
& (Join-Path $PSScriptRoot 'create_android_signing_key.ps1')
$prefix = "$Name="
$matches = @(Get-Content -LiteralPath (Join-Path $root 'android\github-secrets.txt') -Encoding UTF8 |
    Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) })
if ($matches.Count -ne 1) { throw 'Expected exactly one matching secret in the validated export.' }
# Preserve equals signs, backslashes, and spaces inside passwords verbatim.
$value = $matches[0].Substring($prefix.Length)
if ($value.Length -eq 0) { throw 'The validated secret is empty.' }
if ($ValidateOnly) {
    Write-Host "$Name is ready. Clipboard unchanged."
} else {
    Set-Clipboard -Value $value
    Write-Host "Copied ONLY the value for $Name. Paste it into that GitHub secret and save."
    Write-Host 'Do not paste credentials into chat. Clear the clipboard after saving: Set-Clipboard -Value ""'
}
