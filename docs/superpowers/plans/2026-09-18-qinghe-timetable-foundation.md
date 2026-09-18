# 青禾课表基础版本实施计划

## 文件职责

- `lib/main.dart`：应用入口。
- `lib/app.dart`：MaterialApp 与主题入口。
- `lib/core/theme/app_theme.dart`：颜色与组件主题。
- `lib/features/timetable/domain/models.dart`：学期、课程、课程时段与周次规则。
- `lib/features/timetable/data/sample_schedule.dart`：演示数据。
- `lib/features/timetable/presentation/timetable_page.dart`：首个课表页。
- `test/features/timetable/domain/models_test.dart`：领域规则测试。
- `test/features/timetable/presentation/timetable_page_test.dart`：页面测试。

## 实施步骤

1. 用 Flutter stable 初始化 Android/iOS 项目，设置包名 `com.qinghe.timetable`。
2. 先写领域层失败测试，覆盖周次模式和学期日期映射。
3. 实现最小领域模型，使测试通过。
4. 先写页面失败测试，验证标题与课程信息。
5. 实现主题、示例数据和周课表页面，使页面测试通过。
6. 运行格式化、静态分析和全部测试。
7. 构建 Android debug APK，记录真实结果。
8. 初始化 Git，提交本阶段成果；创建并推送到私有 GitHub 仓库。

## 后续阶段

基础版本通过后，按本地数据库与编辑、通知、成都文理学院导入、账户和同步的顺序推进。每一阶段保持可运行、可测试，避免一次引入全部复杂度。

