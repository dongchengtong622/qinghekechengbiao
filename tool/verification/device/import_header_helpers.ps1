param([string]$Serial='15495091960017A')
$ErrorActionPreference='Stop'
$env:ANDROID_USER_HOME='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-user/.android'
$adbPath='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-sdk/platform-tools/adb.exe'
$outputPath=Join-Path (Get-Location) 'docs/verification/import-header-2026-10-09'
function Device-Adb {
  $result=& $adbPath -s $Serial @args
  if($LASTEXITCODE -ne 0){throw "ADB failed: $args"}
  return $result
}
function Read-Ui([string]$name='current') {
  Device-Adb shell uiautomator dump /sdcard/Download/qh-v105-current.xml | Out-Null
  $localPath=Join-Path $outputPath "$name.xml"
  Device-Adb pull /sdcard/Download/qh-v105-current.xml $localPath | Out-Null
  return ([xml](Get-Content -LiteralPath $localPath -Raw)).SelectNodes('//node')
}
function Find-Node($nodes,[string]$label) {
  $found=@($nodes | Where-Object { $_.text -eq $label -or $_.'content-desc' -like "*$label*" })
  if(-not $found.Count){throw "Missing UI: $label"}
  return $found[0]
}
function Tap-Node($node) {
  $coords=@([regex]::Matches($node.bounds,'\d+') | ForEach-Object { [int]$_.Value })
  Device-Adb shell input tap ([int](($coords[0]+$coords[2])/2)) ([int](($coords[1]+$coords[3])/2)) | Out-Null
  Start-Sleep -Milliseconds 200
}
function Capture-Screen([string]$name) {
  Device-Adb shell screencap -p /sdcard/Download/qh-v105-screen.png | Out-Null
  Device-Adb pull /sdcard/Download/qh-v105-screen.png (Join-Path $outputPath "$name.png") | Out-Null
}
function Show-Labels($nodes) {
 $nodes | Where-Object {$_.text -ne '' -or $_.'content-desc' -ne ''} | ForEach-Object {Write-Output "$($_.text) | $($_.'content-desc') | $($_.bounds)"}
}
