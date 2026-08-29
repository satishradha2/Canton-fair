$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$keystorePath = Join-Path $root "android\app\canton-fair-release.jks"
$keyPropertiesPath = Join-Path $root "android\key.properties"
$secretsPath = Join-Path $root "android\github-secrets.txt"
$javaHome = "C:\Users\satis\development\android-studio\jbr"
$keytool = Join-Path $javaHome "bin\keytool.exe"

if (-not (Test-Path $keytool)) {
    throw "keytool.exe was not found at $keytool"
}

if ((Test-Path $keystorePath) -and (Test-Path $keyPropertiesPath)) {
    $keyProperties = ConvertFrom-StringData (Get-Content -Raw $keyPropertiesPath)
    $storePassword = $keyProperties.storePassword
    $keyPassword = $storePassword
    $alias = $keyProperties.keyAlias
} elseif (Test-Path $keystorePath) {
    throw "Keystore already exists at $keystorePath, but $keyPropertiesPath was not found."
} else {
    $storePassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
    $keyPassword = $storePassword
    $alias = "canton-fair"

    & $keytool -genkeypair `
        -v `
        -keystore $keystorePath `
        -storepass $storePassword `
        -keypass $keyPassword `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -alias $alias `
        -dname "CN=Canton Fair CRM, OU=Mobile, O=Canton Fair CRM, L=Guangzhou, S=Guangdong, C=CN"

    @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$alias
storeFile=app/canton-fair-release.jks
"@ | Set-Content -Path $keyPropertiesPath -Encoding ASCII
}

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))

@"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$alias
storeFile=app/canton-fair-release.jks
"@ | Set-Content -Path $keyPropertiesPath -Encoding ASCII

@"
ANDROID_KEYSTORE_BASE64=$keystoreBase64
ANDROID_KEYSTORE_PASSWORD=$storePassword
ANDROID_KEY_PASSWORD=$keyPassword
ANDROID_KEY_ALIAS=$alias
"@ | Set-Content -Path $secretsPath -Encoding ASCII

Write-Host ""
Write-Host "Release keystore:"
Write-Host $keystorePath
Write-Host ""
Write-Host "Saved the exact GitHub repository secret values here:"
Write-Host $secretsPath
Write-Host ""
Write-Host "Add these GitHub repository secrets:"
Write-Host "ANDROID_KEYSTORE_BASE64=$keystoreBase64"
Write-Host "ANDROID_KEYSTORE_PASSWORD=$storePassword"
Write-Host "ANDROID_KEY_PASSWORD=$keyPassword"
Write-Host "ANDROID_KEY_ALIAS=$alias"
Write-Host ""
Write-Host "Keep android/app/canton-fair-release.jks private. It is ignored by git."
