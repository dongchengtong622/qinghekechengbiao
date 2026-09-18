import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class CourseRows extends Table {
  TextColumn get id => text()();
  TextColumn get semesterId =>
      text().withDefault(const Constant('sample-2026-autumn'))();
  TextColumn get sourceType => text().withDefault(const Constant('manual'))();
  TextColumn get externalId => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get teacher => text().withDefault(const Constant(''))();
  IntColumn get colorValue => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SemesterRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get firstWeekStart => dateTime()();
  IntColumn get totalWeeks => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CourseSessionRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get courseId =>
      text().references(CourseRows, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  IntColumn get startSection => integer()();
  IntColumn get endSection => integer()();
  IntColumn get startWeek => integer()();
  IntColumn get endWeek => integer()();
  TextColumn get pattern => text()();
  TextColumn get room => text()();
}

class AppMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [CourseRows, CourseSessionRows, SemesterRows, AppMetadata],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(semesterRows);
        await into(semesterRows).insert(
          SemesterRowsCompanion.insert(
            id: 'sample-2026-autumn',
            name: '2026 秋季学期',
            firstWeekStart: DateTime(2026, 9, 7),
            totalWeeks: 18,
            isActive: const Value(true),
          ),
        );
        await migrator.addColumn(courseRows, courseRows.semesterId);
        await migrator.addColumn(courseRows, courseRows.sourceType);
        await migrator.addColumn(courseRows, courseRows.externalId);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'qinghe_timetable',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
