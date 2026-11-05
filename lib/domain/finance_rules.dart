import 'date_utils.dart';
import 'enums.dart';

/// 依帳單設定算出「今天或之後」最近的一次到期日。
///
/// [anchorMonth]：每季 / 每年帳單的起算月份（'yyyy-MM'），每月帳單可忽略。
DateTime nextDueDate({
  required DateTime today,
  required int dueDay,
  required Recurrence recurrence,
  String? anchorMonth,
}) {
  final t = startOfDay(today);
  final anchor = anchorMonth != null ? parseMonthKey(anchorMonth) : t;
  final step = recurrence.months;

  // 從起算月份往後找，找到第一個 >= 今天的到期日。
  var monthsFromAnchor = 0;
  final diff = (t.year - anchor.year) * 12 + (t.month - anchor.month);
  if (diff > 0) monthsFromAnchor = (diff ~/ step) * step;
  for (var guard = 0; guard < 40; guard++) {
    final m = DateTime(anchor.year, anchor.month + monthsFromAnchor);
    final due = clampedDay(m.year, m.month, dueDay);
    if (!due.isBefore(t)) return due;
    monthsFromAnchor += step;
  }
  throw StateError('unreachable');
}

/// 是否已進入提醒區間（到期日前 N 天內，含當天）。
bool isBillInReminderWindow({
  required DateTime today,
  required DateTime dueDate,
  required int remindDaysBefore,
}) {
  final d = daysBetween(today, dueDate);
  return d >= 0 && d <= remindDaysBefore;
}

/// 信用卡本期帳單區間：上期帳單日隔天 ~ 本期帳單日（含）。
/// 回傳 [start, endExclusive)。
(DateTime, DateTime) creditCardCycle(DateTime today, int billingDay) {
  final t = startOfDay(today);
  var closing = clampedDay(t.year, t.month, billingDay);
  if (t.isAfter(closing)) {
    final next = DateTime(t.year, t.month + 1);
    closing = clampedDay(next.year, next.month, billingDay);
  }
  final prevMonth = DateTime(closing.year, closing.month - 1);
  final prevClosing = clampedDay(prevMonth.year, prevMonth.month, billingDay);
  return (
    prevClosing.add(const Duration(days: 1)),
    closing.add(const Duration(days: 1)),
  );
}

/// 信用卡使用率是否達警戒（預設 80%）。
bool isCreditWarning({
  required int spent,
  required int creditLimit,
  required double warnRatio,
}) {
  if (creditLimit <= 0) return false;
  return spent >= creditLimit * warnRatio;
}

/// 資產是否超過 N 天沒更新（固定任務：每三天更新一次）。
bool isAssetStale(DateTime? lastUpdated, DateTime now, {int days = 3}) {
  if (lastUpdated == null) return true;
  return daysBetween(lastUpdated, now) >= days;
}

String formatMoney(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}\$${buf.toString()}';
}
