import '../domain/models.dart';
import '../domain/school_schedule.dart';

class ImportCourseReview {
  const ImportCourseReview({
    required this.rawText,
    this.fieldsNeedingReview = const {},
  });

  final String rawText;
  final Set<String> fieldsNeedingReview;
}

class ImportPreview {
  const ImportPreview({
    required this.semester,
    required this.courses,
    this.warnings = const [],
    this.replaceExisting = true,
    this.courseReviews = const {},
    this.importedTimes = const [],
    this.timeChoices = const {},
    this.sectionSchedule,
  });

  final SchoolSchedule? sectionSchedule;
  ImportPreview withSectionSchedule(SchoolSchedule value) => ImportPreview(
    semester: semester,
    courses: courses,
    warnings: warnings,
    replaceExisting: replaceExisting,
    courseReviews: courseReviews,
    importedTimes: importedTimes,
    timeChoices: timeChoices,
    sectionSchedule: value,
  );
  final bool replaceExisting;
  final Semester semester;
  final List<Course> courses;
  final List<String> warnings;
  final Map<String, ImportCourseReview> courseReviews;
  final List<SectionRangeTime> importedTimes;
  final Map<String, SectionRangeTime> timeChoices;
}
