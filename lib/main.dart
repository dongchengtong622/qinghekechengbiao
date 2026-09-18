import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/timetable/data/app_database.dart';

void main() {
  runApp(QingheApp(database: AppDatabase()));
}
