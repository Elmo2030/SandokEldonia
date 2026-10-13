/// Xtream JSON is loosely typed (ids as string or number, null ratings), so it is read untyped.
/// `str` mirrors the Swift reader: "" and null are absent, numbers and booleans become their text.
String? str(Object? v) => switch (v) {
      String s => s.isEmpty ? null : s,
      int n => '$n',
      double d => d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15 ? '${d.toInt()}' : '$d',
      bool b => b ? '1' : '0',
      _ => null,
    };

final _intPattern = RegExp(r'^[+-]?\d+$');

/// Like Swift `Int(String)`: no hex, no spaces.
int? parseInt(String? s) => s != null && _intPattern.hasMatch(s) ? int.tryParse(s) : null;

int? intOf(Object? v) => parseInt(str(v));

/// The list of JSON objects, or null when `v` is anything else (one non-object element spoils the list).
List<Map<String, dynamic>>? objectList(Object? v) {
  if (v is! List) return null;
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    if (e is! Map) return null;
    out.add(e.cast<String, dynamic>());
  }
  return out;
}

/// "yyyy-MM-dd HH:mm:ss.SSS" in UTC: how GRDB (the Apple apps) store dates, so a database file stays portable and
/// string comparison orders dates.
String dbDate(DateTime d) {
  final u = d.toUtc();
  String p(int v, int n) => v.toString().padLeft(n, '0');
  return '${p(u.year, 4)}-${p(u.month, 2)}-${p(u.day, 2)} ${p(u.hour, 2)}:${p(u.minute, 2)}:${p(u.second, 2)}.${p(u.millisecond, 3)}';
}

DateTime parseDbDate(String s) => DateTime.parse('${s.replaceFirst(' ', 'T')}Z');
