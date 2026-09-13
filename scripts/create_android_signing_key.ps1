$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$keystorePath = Join-Path $root "android\app\canton-fair-release.jks"
$keyPropertiesPath = Join-Path $root "android\key.properties"
$secretsPath = Join-Path $root "android\github-secrets.txt"
$javaHome = "C:\Users\satis\development\android-studio\jbr"
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $javaHome = $env:JAVA_HOME
}
$keytool = Join-Path $javaHome "bin\keytool.exe"
$java = Join-Path $javaHome "bin\java.exe"

if (-not (Test-Path $keytool)) {
    throw "keytool.exe was not found at $keytool"
}

if ((Test-Path $keystorePath) -and (Test-Path $keyPropertiesPath)) {
    # Validate and export the existing Java properties without changing them.
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
    if ($LASTEXITCODE -ne 0) { throw 'Keystore creation failed. No configuration was written.' }

    @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$alias
storeFile=app/canton-fair-release.jks
"@ | Set-Content -Path $keyPropertiesPath -Encoding ASCII
}

& $java (Join-Path $PSScriptRoot 'ValidateAndroidSigning.java') $keyPropertiesPath $secretsPath
if ($LASTEXITCODE -ne 0) {
    throw 'The existing signing credentials could not decrypt the private key. Restore the original keyPassword in android/key.properties; do not generate a replacement keystore.'
}

Write-Host ""
Write-Host "Release keystore:"
Write-Host $keystorePath
Write-Host ""
Write-Host "Saved the exact GitHub repository secret values here:"
Write-Host $secretsPath
Write-Host ""
Write-Host "Add these GitHub repository secrets:"
Write-Host "ANDROID_KEYSTORE_BASE64"
Write-Host "ANDROID_KEYSTORE_PASSWORD"
Write-Host "ANDROID_KEY_PASSWORD"
Write-Host "ANDROID_KEY_ALIAS"
Write-Host "Use the values from the private file above. Credentials are not printed to the console."
Write-Host ""
Write-Host "Keep android/app/canton-fair-release.jks private. It is ignored by git."
