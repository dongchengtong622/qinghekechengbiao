# 提醒可靠性与本地铃声 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复无提醒及错误状态提示，增加八个铃声预设、本地音乐导入、试听、真实测试通知，并交付 0.5.0+5 测试 APK。

**Architecture:** 保留课表与提醒规划器；调度层改为可观测、逐项协调的注册流程。新增单一 Android 音频桥接层负责系统文件选择、持久音频、试听和通知声音 URI；设置页面消费状态，不自行重复调度。

**Tech Stack:** Flutter/Dart、Drift、flutter_local_notifications、Android Kotlin/MediaPlayer/ContentProvider、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-09-22-reminder-reliability-audio-design.md`（用户已确认）。

## Global Constraints

- 兼容 Android 7.0（API 24）及以上；重点验收 iQOO 8 / Android 14。
- 目标版本：0.5.0+5。保持草稿 PR，不合并 main，不发布应用商店。
- 保留已有课表及设置，不以卸载作为修复。
- 八个预设：系统默认、清脆、柔和、提示音，以及新增晨光、木琴、水滴、短钟声。
- 本地 MP3/WAV/M4A/OGG，最大 20 MiB；取消选择不修改设置。
- 通知注册成功、试听成功、真机通知发声是不同验证结果。
- 不承诺绕过强行停止、通知关闭、勿扰或厂商后台限制。
- 本地 checkout 当前不完整，不能用它替代远端完整仓库跑测试。
- 开始执行时验证隔离分支、恢复完整源码和本计划进度记录；记录远端基线 SHA。
- 没有本地 Flutter SDK 时使用该分支 CI；观察 RED 后才提交对应实现，最后以精确 head SHA 的 GREEN 为准。

## Review Focus

- Release 资源裁剪移除动态音频或图标：Task 1/6 检查真实 APK。
- 部分调度失败或应用退后台：Task 2 验证旧提醒与独立测试任务不被误删。
- 不同通知 ID 哈希冲突、系统任务数量限制：Task 2 检测重复 ID、报告原生错误，不静默成功。
- 本地文件更换、应用重启、跨进程 URI 访问：Task 3/6 检查通知进程读取音频。
- 系统设置返回与权限弹窗交错：Task 4/5 验证只有一个协调入口，状态不会回退成旧快照。

## 文件分工

- `lib/features/reminders/domain/reminder_models.dart`：铃声引用、任务及结果模型。
- `lib/features/reminders/data/reminder_scheduler.dart`：原生通知适配与任务协调。
- 新建 `lib/features/reminders/domain/reminder_diagnostics.dart`：阶段错误和调度报告。
- 新建 `lib/features/reminders/data/ringtone_service.dart`：音频 MethodChannel 的 Dart 接口。
- 新建 `lib/features/reminders/presentation/ringtone_picker.dart`：铃声列表、导入、试听。
- `lib/features/reminders/presentation/reminder_settings_page.dart`：状态、测试、错误详情。
- `lib/features/reminders/domain/reminder_settings_repository.dart`、`lib/features/timetable/data/course_repository.dart`：铃声引用持久化及兼容迁移。
- `lib/app.dart`：唯一生命周期调度入口。
- 新建 `tool/android/MainActivity.kt`、`RingtoneBridge.kt`、`RingtoneProvider.kt`：原生音频桥接源模板。
- `tool/configure_android.dart`：将模板、manifest 配置及资源保留文件注入生成工程。
- 新建 `integration_test/reminder_delivery_test.dart`：真实插件路径验收。
- `pubspec.yaml`、`.github/workflows/flutter-ci.yml`、`README.md`：版本、构建、验收说明。

---

### Task 1: 记录失败阶段并核查旧 Release 产物

**Files:** reminder_diagnostics.dart（新）、reminder_scheduler.dart、reminder_settings_page.dart、test/features/reminders/data/reminder_scheduler_test.dart、test/features/reminders/presentation/reminder_settings_page_test.dart。

**Interfaces:**
- 新增 `ReminderStage { settings, permissions, planning, registration, verification }`。
- 新增 `ReminderFailure(stage, code, message)`，全部字段不可变。
- 新增 `ReminderSyncReport({required int requested, required Set<int> registeredIds, required DateTime? nextAt, required List<ReminderFailure> failures})`。
- 报告只描述已核对的原生注册状态，nextAt 来自已确认注册的课程任务。

- [ ] 从 CI #130 产物取得已交付 APK，使用 Android SDK 的 apkanalyzer/aapt2 检查 manifest、raw 音频和图标；保留输出。
- [ ] 为“权限读取成功、重新调度抛错”写 widget 回归用例：保留权限行，显示“设置提醒失败”，不得显示“无法读取提醒状态”。
```dart
expect(find.text('通知权限'), findsOneWidget);
expect(find.text('设置提醒失败'), findsOneWidget);
expect(find.text('无法读取提醒状态，请稍后重试'), findsNothing);
```
- [ ] 运行 `flutter test test/features/reminders/presentation/reminder_settings_page_test.dart`；Expected: 新断言 FAIL。
- [ ] 将原有大 try/catch 拆分为读取与调度边界，捕获 PlatformException 的 code，其他异常按阶段归类。错误详情排除课程名和原始音频路径。
```dart
try {
  await reschedule();
} on PlatformException catch (error) {
  failure = ReminderFailure(
    ReminderStage.registration,
    error.code,
    '设置提醒失败',
  );
}
```
- [ ] 增加可复制错误详情及重试入口，记录已确认事实和待验证假设；不把资源裁剪、厂商限制等假设写为确诊。
- [ ] 运行上述测试与 scheduler tests；Expected: PASS。提交 `fix: expose reminder failure stages`。

### Task 2: 安全协调通知任务与真实测试通知

**Files:** reminder_scheduler.dart、reminder_diagnostics.dart、reminder_planner.dart、test/features/reminders/data/reminder_scheduler_test.dart、test/features/reminders/domain/reminder_planner_test.dart。

**Interfaces:**
- NotificationGateway 增加 `Future<Set<int>> pendingIds()`、`Future<void> cancel(int id)`、`Future<void> showTest(CourseReminder reminder)`。
- ReminderScheduler 的 `replaceAll(List<CourseReminder>)` 改为 `Future<ReminderSyncReport>`；所有 fake 和调用方同步更新。
- 测试 ID 保留 `0x7ffffffe` 与 `0x7fffffff`；课程 ID 限制在 `1..0x7ffffffd`。
- 新增 `Future<void> sendTest({required RingtoneSelection sound, required Duration delay})`；RingtoneSelection 在 Task 3 定义，Task 2 先保留当前 ReminderSound 参数，Task 3 一并迁移。

- [ ] 增加记录操作顺序的 FakeGateway（pending 集合、failedIds、calls）。先安排旧任务 11/12，目标 12/13，其中 13 抛异常。
```dart
final report = await scheduler.replaceAll(targetReminders);
expect(report.failures, isNotEmpty);
expect(gateway.calls, isNot(contains('cancelAll')));
expect(gateway.pending, contains(11));
expect(gateway.pending, contains(0x7fffffff));
```
- [ ] 运行 scheduler tests；Expected: FAIL，旧实现会 cancelAll。
- [ ] 对目标任务逐项注册，捕获单项异常；查询 pendingIds 核对，只有注册及核对均成功才清理陈旧课程 ID。部分失败保留旧任务并报告部分成功。
```dart
for (final reminder in desired) {
  try {
    await gateway.schedule(reminder, exact: permission.exactAlarmsAllowed);
  } catch (error) {
    failures.add(toRegistrationFailure(error));
  }
}
final confirmed = await gateway.pendingIds();
if (failures.isEmpty && desired.every((r) => confirmed.contains(r.id))) {
  for (final id in staleCourseIds) {
    await gateway.cancel(id);
  }
}
```
- [ ] 显式关闭仅取消课程任务；查询失败时不得执行删除。重复目标 ID 在注册前报错；计划 ID 调整避开测试范围。
- [ ] 测试立即通知调用 show，延迟测试调用 zonedSchedule，时间为 ShanghaiTime.now()+1 分钟；返回前台不可清掉测试 ID。
- [ ] 加入无权限、精确权限撤销竞态、pending 查询异常、重复 ID、部分失败重试及独立测试保留用例。权限竞态只在明确 exact 权限错误后降级，并在报告标明非精确。
- [ ] 运行 planner/scheduler 全部测试；Expected: PASS。提交 `fix: reconcile scheduled reminders without clearing valid alarms`。

### Task 3: 八种预设、持久本地音频与试听

**Files:** reminder_models.dart、ringtone_service.dart（新）、tool/android 三个 Kotlin 模板（新）、configure_android.dart、assets/notification_sounds、reminder_settings_repository.dart、course_repository.dart、pubspec.yaml；新增 test/features/reminders/data/ringtone_service_test.dart，扩展 repository/configurator tests。

**Interfaces:**
- `RingtoneSelection({required String id, required String name, String? resourceName, String? contentUri})`；systemDefault 两个地址都为空，其余恰好一个非空。
- `RingtoneService.importLocal(): Future<RingtoneSelection?>`、`preview(RingtoneSelection): Future<void>`、`stop(): Future<void>`、`resolve(RingtoneSelection): Future<RingtoneSelection>`。
- MethodChannel 名 `com.qinghe.timetable/ringtones`；方法 `importLocal`、`preview`、`stop`、`resolve`。
- Preferences/CourseReminder/planner 使用 RingtoneSelection。repository 改为 `setReminderSound(RingtoneSelection)`；读取旧枚举名称映射到相同预设，不改课程表结构。

- [ ] 写 Dart fake-channel 测试，系统选择取消返回 null，非法结果抛明确错误，旧四种设置保留，八个预设 id 唯一。
```dart
expect(presets.length, 8);
expect(presets.map((s) => s.id).toSet().length, 8);
expect(await service.importLocal(), isNull);
```
- [ ] 运行 `flutter test test/features/reminders/data/ringtone_service_test.dart`；Expected: FAIL，接口不存在。
- [ ] 原生 ACTION_OPEN_DOCUMENT 选择音频；流式复制计数超过 20*1024*1024 立即拒绝，避免信任未知文件大小。用 MediaPlayer.prepare 验证可解码，再原子重命名至 filesDir/ringtones/；失败删除本次临时副本，保留旧选择。
- [ ] 提供只读 ContentProvider：随机不透明 id 映射应用内文件、只支持 openFile(...,"r")，不接受用户路径；非导出、grantUriPermissions，明确对系统通知读取方授权。不要把 FileProvider URI 仅传给插件便认为跨进程成功。
```kotlin
if (mode != "r") throw FileNotFoundException("read only")
val entry = resolveOwnedId(uri.lastPathSegment)
return ParcelFileDescriptor.open(entry, ParcelFileDescriptor.MODE_READ_ONLY)
```
- [ ] URI 与授权可用性需通过跨进程及重启测试确认；若平台实现不能保持授权，停止该方案并报告，不降级成不可读取的 file:// 路径。
- [ ] 试听复用 MediaPlayer：新试听先 release 旧播放器，完成/错误/页面离开 stop；系统默认用系统通知默认 URI。
- [ ] 新增四段短 WAV，并验证可解码、非零音频数据、与现有预设听感不同；不使用未授权音乐。
- [ ] 配置脚本复制 Kotlin 模板及全部七段 WAV，写资源保留 XML；增加幂等性测试。
```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@raw/qinghe_*,@mipmap/ic_launcher" />
```
- [ ] 铃声频道 ID 使用稳定铃声 id（自定义 id 基于导入内容摘要）；替换文件得到新 id/频道，不覆盖旧频道声音。
- [ ] 文件失效时 resolve 返回系统默认并附界面警告；未经提醒不可显示仍使用失效文件。保留仍被通知频道引用的音频，不提前清理。
- [ ] 运行 ringtone/repository/configurator 测试并编译 Android 模板；Expected: PASS。提交 `feat: add persistent ringtones and native preview`。

### Task 4: 单一调度入口与可核对诊断状态

**Files:** app.dart、reminder_settings_page.dart、新建 lib/features/reminders/domain/reminder_controller.dart、test/app_test.dart、新建 test/features/reminders/domain/reminder_controller_test.dart。

**Interfaces:**
- `ReminderController.refresh(): Future<ReminderSyncReport>` 为应用前台、设置变更、导入变更的唯一同步入口。
- `Stream<ReminderSyncReport> get reports` 发布最近结果；相同刷新进行中复用同一 Future，过程中设置变化用 revision 标记完成后重跑最新版本。
- 设置页仅订阅状态，不再在自己的 lifecycle 回调重复调用调度。

- [ ] 写重复刷新和进行中设置变更测试：前者仅一次原生同步，后者最后一次采用新 leadMinutes。
```dart
await Future.wait([controller.refresh(), controller.refresh()]);
expect(fakeScheduler.syncCalls, 1);
```
- [ ] 运行 controller/app tests；Expected: 新测试 FAIL。
- [ ] 使用应用级 WidgetsBindingObserver 调用 controller；初始化失败可重试，不永久缓存失败的 initialize Future。
- [ ] 按阶段发布权限、成功数量、最近错误；下一次时间只取确认为 pending 的计划项。不把残留 ID 无法匹配的任务当作已知下一次。
- [ ] 设置写入失败保留界面旧值；调度失败保留用户选择并显示“设置已保存，提醒同步失败”，可重试。
- [ ] 测试读设置失败、权限被撤销/恢复、初始化失败后重试、foreground 合并、课程修改与设置同时发生。
- [ ] 运行 controller/app/settings tests；Expected: PASS。提交 `fix: centralize reminder refresh and diagnostics`。

### Task 5: 设置页面、铃声试听及测试入口

**Files:** reminder_settings_page.dart、ringtone_picker.dart（新）、test/features/reminders/presentation/reminder_settings_page_test.dart、新建 test/features/reminders/presentation/ringtone_picker_test.dart、README.md。

**Interfaces:** 消费 Task 2 的 sendTest、Task 3 的 RingtoneService 和 Task 4 的 reports/refresh。
- UI keys：`test_notification_now`、`test_notification_delayed`、`import_local_ringtone`、`preview_ringtone`、`stop_ringtone`、`retry_reminders`。
- 延迟测试固定 1 分钟，显示计划时间；不宣称已送达。
- 提前时间继续使用 0/5/10/15/30/60 分钟，不擅自变为多次重复提醒。

- [ ] 写 widget 测试：导入取消保留选中项、导入成功可试听、错误文字可见、离开页停止播放、测试按钮走对应接口。
```dart
await tester.tap(find.byKey(const Key('test_notification_delayed')));
await tester.pumpAndSettle();
expect(fakeScheduler.lastTestDelay, const Duration(minutes: 1));
expect(find.textContaining('测试已安排'), findsOneWidget);
```
- [ ] 运行新增与 settings tests；Expected: FAIL，控件不存在。
- [ ] 预设列表每行试听，另设停止；导入按钮显示忙碌状态防止重复 picker，mounted 检查覆盖所有异步完成分支。
- [ ] 状态区显示已注册数量、下一次时间、同步失败原因、重试/复制详情。强调试听用媒体播放，不代表通知渠道可响。
- [ ] 展示 iQOO 指引：允许通知及渠道声音、允许后台运行、检查电量限制与勿扰；不依赖臆造系统深链。
- [ ] 运行 widget tests，覆盖窄屏、长音乐名、字体放大与滚动后按钮点击；Expected: PASS。提交 `feat: add ringtone preview and notification self-check UI`。

### Task 6: Release 验证、版本与交付

**Files:** pubspec.yaml、flutter-ci.yml、test/tool/configure_android_test.dart、新建 integration_test/reminder_delivery_test.dart、README.md。

**Interfaces:** 输出 `qinghe-timetable-0.5.0-universal.apk`、`qinghe-timetable-0.5.0-arm64.apk`、`qinghe-timetable-0.5.0.aab`。

- [ ] 更新发布配置断言至 0.5.0+5 和三个新文件名，运行 tool tests；Expected: FAIL，旧版本。
- [ ] 更新版本与构建名；每次 apk 构建后立即复制产物，避免后一次覆盖通用版。
- [ ] 在 CI 最終 APK 使用 apkanalyzer/aapt2 验证 minSdk=24、versionCode=5、versionName=0.5.0、七段 raw WAV、通知接收器、音频 provider 和图标。
```bash
apkanalyzer manifest min-sdk qinghe-timetable-0.5.0-universal.apk
apkanalyzer manifest version-code qinghe-timetable-0.5.0-universal.apk
apksigner verify --print-certs qinghe-timetable-0.5.0-universal.apk
```
Expected: 24、5、签名验证成功。将证书摘要与旧 APK 对比；不一致明确报告覆盖安装限制，不索取或重建未知签名。
- [ ] 对 API 24/26/31/33/34 与可用较新系统跑原生通知集成测试，检查 pending、延迟任务、重启恢复、内容 URI 跨进程读取；不能运行的版本记录“未验证”。
- [ ] 独立列出 iQOO 实测清单：立即、1 分钟锁屏、真实课前 30 分钟、默认/预设/本地音乐、重启后。没有手机连接时由用户验收，不能写“已通过”。
- [ ] 全量执行：
```bash
dart format lib test tool integration_test
git diff --exit-code -- '*.dart'
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --reporter expanded
flutter build apk --release
flutter build apk --release --target-platform android-arm64
flutter build appbundle --release
```
Expected: 全部 exit 0；精确 head SHA 的 CI 通过。
- [ ] 全分支审查；Critical/Important 修复先 RED 再 GREEN。独立审查不可用时明确标注自审局限。
- [ ] 下载产物、校验 ZIP/哈希/包版本，保存最终文件；提交 README 中已运行与未运行的验证记录。
- [ ] 交付测试 APK、arm64 备选、AAB、PR 链接及真机清单，不合并 main。

## 自审与执行交接

覆盖检查：故障根因证据 Task 1；无损协调 Task 2；本地音频/八预设 Task 3；权限和生命周期 Task 4；试听和测试 UI Task 5；Android 兼容、版本、签名与产物 Task 6。
接口变化需在单个任务中同步所有 fake/消费者；Task 2 的声音参数在 Task 3 完成统一迁移。
根因尚未确诊：如果日志或 APK 检查揭示与上述故障机制不同的原因，先记录证据并调整最小修复，不盲改系统权限。
推荐 Native：由当前会话按顺序实现，末尾单次全分支审查；任务间接口依赖紧密。
状态：计划已写，等待用户审阅并选择执行方式；尚未开始功能实现。
