# 青禾课表

面向大学生的 Android / iOS 智能课程表。当前版本支持课程表导入、按周查看和 Android 课程提醒。

## 当前状态

- Flutter 双平台工程
- 学期、课程与上课时段模型
- 每周、单周、双周判断
- 可选择任意教学周，并一键回到本周
- 支持成都文理学院 Excel 课表导入
- 支持 Android 通知权限、精确闹钟权限与四种提醒铃声

## 本地运行

```bash
flutter create --platforms=android --org com.qinghe --project-name qinghe_timetable .platform_template
cp -R .platform_template/android ./android
dart run tool/configure_android.dart
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

## 构建 Android 安装包

```bash
flutter build apk --release
flutter build apk --release --target-platform android-arm64
flutter build appbundle --release
```

CI 会分别保留通用 APK、arm64 APK 和用于应用商店发布的 AAB，版本号为 `0.4.0+4`。

详细设计和后续路线见 `docs/superpowers/`。

