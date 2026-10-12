$ErrorActionPreference='Stop'
$toolsRoot='C:/Users/DCT13/AppData/Local/Temp/qh09t'
$javaRoot=(Get-ChildItem "$toolsRoot/jdk" -Directory | Select-Object -First 1).FullName
$modules="$toolsRoot/gradle-cache/caches/modules-2/files-2.1"
$compilerJars=@()
foreach($group in @('org.jetbrains.kotlin','org.jetbrains.kotlinx','org.jetbrains.intellij.deps','org.jetbrains')) {
  if (-not (Test-Path "$modules/$group")) { continue }
  foreach($artifact in (Get-ChildItem "$modules/$group" -Directory)) {
    $versions=@(Get-ChildItem $artifact.FullName -Directory | Sort-Object Name -Descending)
    $version=$versions | Where-Object Name -eq '2.4.0' | Select-Object -First 1
    if (-not $version) { $version=$versions | Select-Object -First 1 }
    $compilerJars+=@(Get-ChildItem $version.FullName -Recurse -Filter '*.jar' | Select-Object -ExpandProperty FullName)
  }
}
$compilerJars=@($compilerJars | Where-Object { $_ -match '(kotlin-compiler-embeddable|kotlin-stdlib|kotlin-reflect|kotlin-script-runtime|kotlinx-coroutines-core|trove4j|annotations-)' })
$dependencies=@(Get-ChildItem "$modules/junit","$modules/org.hamcrest","$modules/org.json" -Recurse -Filter '*.jar' | Select-Object -ExpandProperty FullName)
$dependencies+=@($compilerJars | Where-Object { $_ -match 'kotlin-stdlib[-\\]|annotations-' })
$outputPath='build/native-unit-tests'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$sourceFiles=@('AlarmPolicy','AlarmJournal','WidgetSnapshotLogic','LegacyImportCleanup','SerialAlarmExecutor') | ForEach-Object { "tool/android/$_.kt" }
$testFiles=@(Get-ChildItem android/app/src/test/kotlin/com/qinghe/qinghe_timetable -Filter '*Test.kt' | Select-Object -ExpandProperty FullName)
& "$javaRoot/bin/java.exe" -cp ($compilerJars -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath ($dependencies -join ';') -d "$outputPath/tests.jar" @sourceFiles @testFiles
if ($LASTEXITCODE -ne 0) { throw 'Native test compilation failed' }
$testClasses=@(Get-ChildItem android/app/src/test/kotlin/com/qinghe/qinghe_timetable -Filter '*Test.kt' | ForEach-Object { 'com.qinghe.qinghe_timetable.'+$_.BaseName })
& "$javaRoot/bin/java.exe" -cp ((@("$outputPath/tests.jar")+$dependencies) -join ';') org.junit.runner.JUnitCore @testClasses
if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
