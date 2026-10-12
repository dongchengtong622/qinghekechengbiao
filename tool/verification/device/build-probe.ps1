$ErrorActionPreference='Stop'
. "$PSScriptRoot/../../../docs/preparation/v1.0.1/env-v101.ps1"
$qingheSdkTools=Join-Path $env:ANDROID_HOME 'build-tools/36.0.0'
$qingheAndroidJar=Join-Path $env:ANDROID_HOME 'platforms/android-36/android.jar'
$qingheProbeSource=Join-Path $qingheDevRoot 'tool/verification/device'
$qingheOutput=Join-Path $qingheDevRoot 'build/device-verification'
New-Item -ItemType Directory -Path "$qingheOutput/classes","$qingheOutput/dex","$qingheOutput/assets" -Force | Out-Null
$qingheJava=(Get-Content -LiteralPath "$qingheProbeSource/VerificationInstrumentation.java" -Raw)
[IO.File]::WriteAllText("$qingheOutput/VerificationInstrumentation.java",$qingheJava,[Text.UTF8Encoding]::new($false))
& "$env:JAVA_HOME/bin/javac.exe" -encoding UTF-8 -source 8 -target 8 -classpath $qingheAndroidJar -d "$qingheOutput/classes" "$qingheOutput/VerificationInstrumentation.java"
if($LASTEXITCODE -ne 0){throw 'Verification Java compile failed'}
& "$env:JAVA_HOME/bin/jar.exe" cf "$qingheOutput/verification.jar" -C "$qingheOutput/classes" .
& "$qingheSdkTools/d8.bat" --lib $qingheAndroidJar --min-api 24 --output "$qingheOutput/dex" "$qingheOutput/verification.jar"
if($LASTEXITCODE -ne 0){throw 'Verification dex failed'}
& "$qingheSdkTools/aapt2.exe" link -o "$qingheOutput/test-unsigned.apk" --manifest "$qingheProbeSource/AndroidManifest.xml" -I $qingheAndroidJar -A "$qingheOutput/assets" --min-sdk-version 24 --target-sdk-version 36
if($LASTEXITCODE -ne 0){throw 'Verification manifest failed'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$qingheZip=[IO.Compression.ZipFile]::Open("$qingheOutput/test-unsigned.apk",[IO.Compression.ZipArchiveMode]::Update)
try{[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($qingheZip,"$qingheOutput/dex/classes.dex",'classes.dex') | Out-Null}finally{$qingheZip.Dispose()}
& "$qingheSdkTools/zipalign.exe" -f -p 4 "$qingheOutput/test-unsigned.apk" "$qingheOutput/test-aligned.apk"
& "$qingheSdkTools/apksigner.bat" sign --ks "$env:ANDROID_USER_HOME/debug.keystore" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$qingheOutput/qinghe-device-verification.apk" "$qingheOutput/test-aligned.apk"
if($LASTEXITCODE -ne 0){throw 'Verification signing failed'}
Get-Item -LiteralPath "$qingheOutput/qinghe-device-verification.apk" | Select-Object Name,Length

