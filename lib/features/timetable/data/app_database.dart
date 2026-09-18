import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class CourseRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get teacher => text().withDefault(const Constant(''))();
  IntColumn get colorValue => integer()();

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

@DriftDatabase(tables: [CourseRows, CourseSessionRows, AppMetadata])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'qinghe_timetable',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
