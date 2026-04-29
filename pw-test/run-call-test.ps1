# Cross-platform call test launcher
# Run: .\run-call-test.ps1

$emulatorExe = "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe"
$adbExe = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$avdName = "Medium_Phone_API_36.0"

# 1. Check if emulator is already running
$devs = & $adbExe devices 2>$null
if ($devs -match "emulator-5554") {
    Write-Host "OK: Emulator already running" -ForegroundColor Green
} else {
    Write-Host "Starting emulator $avdName..." -ForegroundColor Cyan
    Start-Process $emulatorExe -ArgumentList "-avd",$avdName,"-no-audio"

    Write-Host "Waiting for emulator..." -ForegroundColor Yellow
    $found = $false
    for ($i = 0; $i -lt 36; $i++) {
        Start-Sleep -Seconds 5
        $devs = & $adbExe devices 2>$null
        if ($devs -match "emulator-5554\s+device") {
            $found = $true
            break
        }
        Write-Host "." -NoNewline
    }
    if (-not $found) {
        Write-Host "`nFAIL: Emulator did not start" -ForegroundColor Red
        exit 1
    }
    Write-Host "`nOK: Emulator connected" -ForegroundColor Green
}

# Wait for boot
Write-Host "Waiting for boot..." -ForegroundColor Yellow
for ($i = 0; $i -lt 40; $i++) {
    $booted = & $adbExe shell getprop sys.boot_completed 2>$null
    if ($booted -match "1") { break }
    Start-Sleep -Seconds 3
}
Start-Sleep -Seconds 3
Write-Host "OK: Emulator booted" -ForegroundColor Green

# 2. Check Appium
$appiumOk = $false
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:4723/status" -TimeoutSec 3 -UseBasicParsing
    $appiumOk = $true
    Write-Host "OK: Appium running on 4723" -ForegroundColor Green
} catch {
    Write-Host "Starting Appium..." -ForegroundColor Cyan
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c","npx appium"
    Start-Sleep -Seconds 8
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:4723/status" -TimeoutSec 5 -UseBasicParsing
        Write-Host "OK: Appium started" -ForegroundColor Green
    } catch {
        Write-Host "FAIL: Appium not available" -ForegroundColor Red
        exit 1
    }
}

# 3. Check web server
$webOk = $false
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:58585" -TimeoutSec 3 -UseBasicParsing
    $webOk = $true
    Write-Host "OK: Web server running on 58585" -ForegroundColor Green
} catch {
    Write-Host "Starting web server..." -ForegroundColor Cyan
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c","cd /d D:\PROJECTS\STEALTH\pw-test && node serve-static-web.mjs"
    Start-Sleep -Seconds 3
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:58585" -TimeoutSec 5 -UseBasicParsing
        Write-Host "OK: Web server started" -ForegroundColor Green
    } catch {
        Write-Host "FAIL: Web server not available" -ForegroundColor Red
        exit 1
    }
}

# 4. Run the test
Write-Host "`nRunning cross-platform call test..." -ForegroundColor Cyan
Set-Location "D:\PROJECTS\STEALTH\pw-test"
node appium-web-call-test.mjs

Write-Host "`nDone. Check screenshots in pw-test/ directory." -ForegroundColor Green
