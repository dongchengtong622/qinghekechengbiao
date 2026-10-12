# 青禾课表 · V1.0.5

面向大学生的 Android 课表应用。当前最新版本：**1.0.5+18**。

## 下载并安装

**[下载最新版 Android 安装包（ARM64）](https://github.com/dongchengtong622/qinghekechengbiao/raw/refs/heads/main/releases/v1.0.5/qinghe-timetable-v1.0.5-arm64.apk)**

[查看 V1.0.5 发布页](https://github.com/dongchengtong622/qinghekechengbiao/releases/tag/v1.0.5) · [查看更新说明](VERSION.md)

适用于 Android 7.0 及以上的 ARM64 手机。下载 APK 后在手机打开，按系统提示允许对应来源安装。GitHub 网页提供下载入口，安装仍需在手机确认。

本包为现有开发版，保留课程编辑、Excel 导入、课表切换、提醒、小组件和本地备份等已有功能。课程和设置保存在手机本地。

文件大小：14,615,380 字节；APK versionCode：2018。

SHA256：`2CBE0A4ADC1C365FF627D3EE408DFE37E57A782FE33117916C342C8D00483659`

## 本次更新

- 修复首次设置学期时示例课程对学期周数的限制。
- 改善 HTML、GBK/GB2312、Big5、UTF-16 及 SpreadsheetML 格式的 .xls 导入兼容性。
- 修复周表标题与“回到本周”入口的布局。

## 源码与开发

本仓库 main 分支已同步 V1.0.5 开发目录中的 Flutter 源码、Android 工程、资源及测试，安装包位于 releases/v1.0.5/。

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

Android 工程已包含在仓库中，不需要重新生成。构建使用 Java 17。签名私钥、机器路径、缓存、设备日志和旧版交付包未纳入源码。

当前构建配置使用开发签名；自行构建的签名可能与已发布 APK 不同，因此不保证能直接覆盖安装，安装前应做好本地备份。

### Android 工程恢复

仅当 Android 工程丢失时，生成临时模板并恢复 android 目录，然后应用项目配置：

```bash
flutter create --platforms=android --org com.qinghe --project-name qinghe_timetable .platform_template
# 将 .platform_template/android 恢复到 android 目录后执行
dart run tool/configure_android.dart
```
