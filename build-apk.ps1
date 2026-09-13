# Builds the mobile APK: static web bundle -> APK assets -> debug APK.
#   powershell -ExecutionPolicy Bypass -File build-apk.ps1            # full build
#   powershell -ExecutionPolicy Bypass -File build-apk.ps1 -SkipWeb   # reuse apk/stage
param(
    [switch]$SkipWeb
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 1. Static web bundle (entry: apk/www, output: apk/stage).
if (-not $SkipWeb) {
    Write-Host '==> vite build (apk bundle)'
    & npx.cmd vite build --config vite.apk.config.ts
    if ($LASTEXITCODE -ne 0) { throw 'vite build failed' }
}
if (-not (Test-Path 'apk/stage/index.html')) { throw 'apk/stage/index.html missing - rerun without -SkipWeb' }

# 2. Stage into the APK assets root; MainActivity serves /X from asset file X,
#    and the document opens at https://appassets.androidplatform.net/www/index.html.
Write-Host '==> staging web bundle into APK assets'
$assets = 'apk/app/src/main/assets'
if (Test-Path $assets) { Remove-Item -Recurse -Force $assets }
New-Item -ItemType Directory -Force "$assets/www" | Out-Null
Copy-Item -Path 'apk/stage/*' -Destination $assets -Recurse -Force
Move-Item -Force "$assets/index.html" "$assets/www/index.html"

# 3. JDK 17+ (AGP 8 requires it): prefer an existing JAVA_HOME, then ~/.jdks.
Write-Host '==> locating JDK 17+'
$jdk = $null
if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME/bin/java.exe")) { $jdk = $env:JAVA_HOME }
if (-not $jdk -and (Test-Path "$env:USERPROFILE/.jdks")) {
    $found = Get-ChildItem "$env:USERPROFILE/.jdks" -Directory |
        Where-Object { Test-Path "$($_.FullName)/bin/java.exe" } |
        Sort-Object { if ($_.Name -match 'temurin-17') { 0 } else { 1 } }
    if ($found) { $jdk = $found[0].FullName }
}
if (-not $jdk) { throw 'JDK 17+ not found. Install to %USERPROFILE%\.jdks\temurin-17 or set JAVA_HOME.' }
$env:JAVA_HOME = $jdk
Write-Host "    JAVA_HOME=$jdk"

# 4. Debug APK (gradle wrapper uses the Tencent mirror; artifacts are cached
#    locally so repeat builds run offline). Output goes to a log file because
#    the spawned daemon inherits pipe handles and would hang PowerShell.
Write-Host '==> gradle assembleDebug'
$gradleLog = Join-Path $env:TEMP 'poolcore-gradle.log'
cmd /c "apk\gradlew.bat -p apk assembleDebug --console=plain > `"$gradleLog`" 2>&1"
if ($LASTEXITCODE -ne 0) {
    Get-Content $gradleLog -Tail 40
    throw 'gradle build failed'
}
Get-Content $gradleLog -Tail 3

# 5. Copy next to the project for easy install.
$out = 'dist-apk'
New-Item -ItemType Directory -Force $out | Out-Null
$apk = Get-ChildItem 'apk/app/build/outputs/apk/debug/*-debug.apk' | Select-Object -First 1
Copy-Item $apk.FullName "$out/BeyondTheBasin-PoolCore-debug.apk" -Force
Write-Host "APK ready: $out\BeyondTheBasin-PoolCore-debug.apk"
Write-Host 'Install: adb install -r dist-apk\BeyondTheBasin-PoolCore-debug.apk'
