import '../domain/models.dart';

class ImportPreview {
  const ImportPreview({
    required this.semester,
    required this.courses,
    this.warnings = const [],
  });

  final Semester semester;
  final List<Course> courses;
  final List<String> warnings;
}
