param([ValidateSet('before','after')][string]$Mode='before',[string]$Serial='15495091960017A')
$ErrorActionPreference='Stop'
$env:ANDROID_USER_HOME='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-user/.android'
$adbPath='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-sdk/platform-tools/adb.exe'
$appId='com.qinghe.qinghe_timetable'
$outputPath=Join-Path (Get-Location) (Join-Path 'device-verification' $Serial)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
function Device-Adb {
  $result=& $adbPath -s $Serial @args
  if ($LASTEXITCODE -ne 0) { throw "ADB failed: $args" }
  return $result
}
function Read-Ui([string]$name) {
  Device-Adb shell uiautomator dump /sdcard/Download/qinghe-switch-test.xml | Out-Null
  $localPath=Join-Path $outputPath "$name.xml"
  Device-Adb pull /sdcard/Download/qinghe-switch-test.xml $localPath | Out-Null
  return ([xml](Get-Content -LiteralPath $localPath -Raw)).SelectNodes('//node')
}
function Find-Node($nodes,[string]$label) {
  $found=@($nodes | Where-Object { $_.text -eq $label -or $_.'content-desc' -like "*$label*" })
  if ($found.Count -eq 0) { throw "Missing UI: $label" }
  return $found[0]
}
function Tap-Node($node) {
  $coords=@([regex]::Matches($node.bounds,'\d+') | ForEach-Object { [int]$_.Value })
  Device-Adb shell input tap ([int](($coords[0]+$coords[2])/2)) ([int](($coords[1]+$coords[3])/2)) | Out-Null
  Start-Sleep -Milliseconds 150
}
function Open-Reminders {
  Device-Adb shell am start -n "$appId/.MainActivity" | Out-Null
  $nodes=Read-Ui 'home'
  $legacyEntry=@($nodes | Where-Object { $_.'content-desc' -in @('提醒已开启','提醒已关闭') })
  if ($legacyEntry.Count -and -not @($nodes | Where-Object { $_.'content-desc' -eq '更多' }).Count) {
    Tap-Node $legacyEntry[0]
    return Read-Ui 'reminders'
  }
  for ($i=0; $i -lt 5 -and -not @($nodes | Where-Object { $_.'content-desc' -eq '更多' }).Count; $i++) {
    Device-Adb shell input keyevent 4 | Out-Null
    $nodes=Read-Ui 'return-home'
  }
  Tap-Node (Find-Node $nodes '更多')
  Tap-Node (Find-Node (Read-Ui 'menu') '课程提醒')
  return Read-Ui 'reminders'
}
function Read-Switch($nodes,[string]$label) {
  $node=Find-Node $nodes $label
  if ($node.class -ne 'android.widget.Switch') { throw "Expected switch: $label" }
  return ($node.checked -eq 'true')
}
function Assert-Switch($nodes,[string]$label,[bool]$expected) {
  if ((Read-Switch $nodes $label) -ne $expected) { throw "Wrong switch state: $label expected $expected" }
  if ((Find-Node $nodes $label).enabled -ne 'true') { throw "Switch remained disabled: $label" }
}
$nodes=Open-Reminders
$enabled=Read-Switch $nodes '上课提醒'
$holiday=if ($enabled) { Read-Switch $nodes '法定节假日静默' } else { $null }
$baselineFile=Join-Path $outputPath 'original-switches.json'
if ($Mode -eq 'before') {
  @{enabled=$enabled;holiday=$holiday} | ConvertTo-Json | Set-Content -LiteralPath $baselineFile -Encoding utf8
  Write-Output "Saved original settings: reminder=$enabled holiday=$holiday"
  exit
}
$original=Get-Content -LiteralPath $baselineFile -Raw | ConvertFrom-Json
if ($enabled -ne $original.enabled -or $holiday -ne $original.holiday) { throw 'Upgrade changed reminder preferences' }
try {
  if (-not $enabled) {
    Tap-Node (Find-Node $nodes '上课提醒')
    $nodes=Read-Ui 'temporarily-enabled'
    Assert-Switch $nodes '上课提醒' $true
    $enabled=$true
    $holiday=Read-Switch $nodes '法定节假日静默'
    $original.holiday=$holiday
  }
  Device-Adb shell dumpsys gfxinfo $appId reset | Out-Null
  for ($i=0;$i -lt 4;$i++) {
    Tap-Node (Find-Node $nodes '上课提醒')
    $nodes=Read-Ui "main-$i"
    $enabled = -not $enabled
    Assert-Switch $nodes '上课提醒' $enabled
    if (-not $enabled -and @($nodes | Where-Object { $_.'content-desc' -like '*法定节假日静默*' }).Count) { throw 'Disabled settings did not collapse' }
  }
  if ($enabled) {
    for ($i=0;$i -lt 4;$i++) {
      Tap-Node (Find-Node $nodes '法定节假日静默')
      $nodes=Read-Ui "holiday-$i"
      $holiday = -not $holiday
      Assert-Switch $nodes '法定节假日静默' $holiday
    }
    $node=Find-Node $nodes '法定节假日静默'
    for ($i=0;$i -lt 10;$i++) { Tap-Node $node }
    $nodes=Read-Ui 'rapid-holiday'
    Assert-Switch $nodes '法定节假日静默' $original.holiday
  }
  Device-Adb shell dumpsys gfxinfo $appId framestats | Set-Content (Join-Path $outputPath 'switch-frames.txt')
  Device-Adb shell input keyevent 4 | Out-Null
  Device-Adb shell am force-stop $appId | Out-Null
  $nodes=Open-Reminders
  Assert-Switch $nodes '上课提醒' $enabled
  if ($enabled) { Assert-Switch $nodes '法定节假日静默' $original.holiday }
  Device-Adb shell screencap -p /sdcard/Download/qinghe-fixed-reminders.png | Out-Null
  Device-Adb pull /sdcard/Download/qinghe-fixed-reminders.png (Join-Path $outputPath 'fixed-reminders.png') | Out-Null
  Device-Adb shell input keyevent 4 | Out-Null
  Tap-Node (Find-Node (Read-Ui 'widget-home') '更多')
  Tap-Node (Find-Node (Read-Ui 'widget-menu') '桌面小组件')
  $nodes=Read-Ui 'widget-tutorial'
  Find-Node $nodes '手动添加教程' | Out-Null
  Find-Node $nodes '找到“青禾课表”' | Out-Null
  $beforeWidgets=Device-Adb shell dumpsys appwidget
  Tap-Node (Find-Node $nodes '刷新组件数据')
  $nodes=Read-Ui 'widget-refreshed'
  Find-Node $nodes '组件数据已更新' | Out-Null
  Device-Adb shell screencap -p /sdcard/Download/qinghe-fixed-widgets.png | Out-Null
  Device-Adb pull /sdcard/Download/qinghe-fixed-widgets.png (Join-Path $outputPath 'fixed-widgets.png') | Out-Null
  Write-Output 'PASS: both switches toggle repeatedly, rapid taps persist, restart retains settings, widget tutorial and refresh work.'
} finally {
  $nodes=Open-Reminders
  if ((Read-Switch $nodes '上课提醒') -ne $original.enabled) {
    Tap-Node (Find-Node $nodes '上课提醒')
    $nodes=Read-Ui 'restored-main'
  }
  if ($original.enabled -and (Read-Switch $nodes '法定节假日静默') -ne $original.holiday) {
    Tap-Node (Find-Node $nodes '法定节假日静默')
    $nodes=Read-Ui 'restored-holiday'
  }
}


