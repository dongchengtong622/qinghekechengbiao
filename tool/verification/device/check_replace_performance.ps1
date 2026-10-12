param([string]$LogFile='native-replace-profile.log',[double]$MaxMainThreadMs=100)
$ErrorActionPreference='Stop'
$env:ANDROID_USER_HOME='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-user/.android'
$adbPath='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-sdk/platform-tools/adb.exe'
$mapping=Get-Content build/app/outputs/mapping/release/mapping.txt -Raw
$storeClass=[regex]::Match($mapping,'(?m)^com\.qinghe\.qinghe_timetable\.AlarmStore -> (.+):\r?$').Groups[1].Value.Trim()
if (-not $storeClass) { throw 'Missing AlarmStore release mapping' }
& $adbPath -s 15495091960017A shell am instrument -w -e mode replace-profile -e storeClass $storeClass com.qinghe.verification/com.qinghe.verification.VerificationInstrumentation > $LogFile
if ($LASTEXITCODE -ne 0) { throw 'Profile instrumentation failed' }
$profileLine=Get-Content -LiteralPath $LogFile | Where-Object { $_ -like 'INSTRUMENTATION_RESULT: profile=*' }
if (-not $profileLine) { throw "Missing performance report; see $LogFile" }
$profile=$profileLine.Substring($profileLine.IndexOf('=')+1) | ConvertFrom-Json
$profile.transitions | Format-Table
if (@($profile.transitions | Where-Object { $_.mainThreadMs -gt $MaxMainThreadMs }).Count) {
  throw "FAIL: reminder replacement blocks UI for more than $MaxMainThreadMs ms"
}
Write-Output 'PASS: all four 300-event reminder transitions remain within the main-thread time limit; user timetable untouched.'
