import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/timetable/data/sample_schedule.dart';
import 'features/timetable/presentation/timetable_page.dart';

class QingheApp extends StatelessWidget {
  const QingheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青禾课表',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: TimetablePage(
        semester: sampleSemester,
        courses: sampleCourses,
        displayWeek: 3,
      ),
    );
  }
}
