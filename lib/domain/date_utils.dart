/// 日期工具。資料庫一律用：
/// - 時間點：毫秒 epoch（int）
/// - 日期：'yyyy-MM-dd'
/// - 月份：'yyyy-MM'
library;

String _two(int v) => v.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String monthKey(DateTime d) => '${d.year}-${_two(d.month)}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime parseMonthKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1]);
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

/// 下個月第一天（用 DateTime 的月份溢位處理跨年）。
DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 回傳 [d] 那個月的第 [day] 天；超過月底就用月底（例如 31 號在 2 月 → 28/29 號）。
DateTime clampedDay(int year, int month, int day) {
  final last = daysInMonth(year, month);
  return DateTime(year, month, day > last ? last : day);
}

String previousMonthKey(String key) {
  final d = parseMonthKey(key);
  return monthKey(DateTime(d.year, d.month - 1));
}

String nextMonthKey(String key) {
  final d = parseMonthKey(key);
  return monthKey(DateTime(d.year, d.month + 1));
}

/// 兩個日期之間（以日曆日計）相差幾天。用 UTC 避免夏令時間誤差。
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}
