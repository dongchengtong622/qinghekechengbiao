/// Parses numeric section labels shared by Excel formats.
class SectionNumberParser {
  static int? periodNumber(String value) {
    final number = int.tryParse(value);
    if (number != null) return number;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) return 10 + (digits[value.substring(1)] ?? 0);
    return digits[value];
  }
}
