import 'date_utils.dart';
import 'enums.dart';
import 'finance_rules.dart';

/// 一則要排程的本地通知。
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.kind,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final NotificationKind kind;

  @override
  String toString() => 'Notif($id ${kind.name} $at "$title")';
}

enum NotificationKind { bill, daily, asset }

/// 排程需要的帳單資訊（與資料層解耦）。
class BillForPlan {
  const BillForPlan({
    required this.id,
    required this.name,
    required this.dueDay,
    required this.remindDaysBefore,
    required this.recurrence,
    required this.anchorMonth,
    required this.paidDueDates,
    this.amount,
  });

  final String id;
  final String name;
  final int? amount;
  final int dueDay;
  final int remindDaysBefore;
  final Recurrence recurrence;
  final String anchorMonth;

  /// 已繳的到期日（'yyyy-MM-dd'）。
  final Set<String> paidDueDates;
}

class NotificationPlanInput {
  const NotificationPlanInput({
    required this.now,
    required this.petName,
    required this.dailyEnabled,
    required this.dailyTime,
    required this.recordedToday,
    required this.bills,
    required this.oldestAssetUpdate,
  });

  final DateTime now;
  final String petName;
  final bool dailyEnabled;

  /// 'HH:mm'
  final String dailyTime;
  final bool recordedToday;
  final List<BillForPlan> bills;

  /// 沒有資產帳戶時為 null。
  final DateTime? oldestAssetUpdate;
}

/// 每次排程往後看幾天。APP 每次回到前景 / 進背景時都會重排。
const int notificationHorizonDays = 14;

/// 帳單與資產提醒的時間（避開深夜）。
const int billNotifyHour = 9;
const int assetNotifyHour = 20;

/// Android 對單一 APP 的排程數量有上限，保守一點。
const int maxPlannedNotifications = 60;

(int, int) parseHm(String hm) {
  final p = hm.split(':');
  final h = int.tryParse(p.first) ?? 21;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return (h.clamp(0, 23), m.clamp(0, 59));
}

List<PlannedNotification> planNotifications(NotificationPlanInput i) {
  final out = <PlannedNotification>[];
  final today = startOfDay(i.now);
  final horizon = today.add(const Duration(days: notificationHorizonDays));
  var nextId = 1;

  // ---- 每日記帳提醒 ----
  if (i.dailyEnabled) {
    final (h, m) = parseHm(i.dailyTime);
    for (var d = 0; d < notificationHorizonDays; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final at = DateTime(day.year, day.month, day.day, h, m);
      if (!at.isAfter(i.now)) continue;
      if (d == 0 && i.recordedToday) continue;
      out.add(PlannedNotification(
        id: nextId++,
        at: at,
        title: '${i.petName} 在等你記帳',
        body: '今天花了什麼？記一筆就能拿到道具。沒花錢的話，按「本日無支出」也可以喔！',
        kind: NotificationKind.daily,
      ));
    }
  }

  // ---- 帳單提醒 ----
  for (final b in i.bills) {
    var cursor = today;
    while (true) {
      final due = nextDueDate(
        today: cursor,
        dueDay: b.dueDay,
        recurrence: b.recurrence,
        anchorMonth: b.anchorMonth,
      );
      if (due.isAfter(horizon.add(Duration(days: b.remindDaysBefore)))) break;
      if (!b.paidDueDates.contains(dateKey(due))) {
        final amount = b.amount == null ? '' : '（${formatMoney(b.amount!)}）';
        final remindDay = due.subtract(Duration(days: b.remindDaysBefore));
        final remindAt = DateTime(remindDay.year, remindDay.month, remindDay.day, billNotifyHour);
        if (b.remindDaysBefore > 0 && remindAt.isAfter(i.now)) {
          out.add(PlannedNotification(
            id: nextId++,
            at: remindAt,
            title: '帳單提醒：${b.name}',
            body: '${b.remindDaysBefore} 天後（${due.month}/${due.day}）到期$amount',
            kind: NotificationKind.bill,
          ));
        }
        final dueAt = DateTime(due.year, due.month, due.day, billNotifyHour);
        if (dueAt.isAfter(i.now)) {
          out.add(PlannedNotification(
            id: nextId++,
            at: dueAt,
            title: '今天到期：${b.name}',
            body: '記得繳費$amount，繳完可以一鍵記帳。',
            kind: NotificationKind.bill,
          ));
        }
      }
      cursor = due.add(const Duration(days: 1));
    }
  }

  // ---- 資產更新提醒（超過 3 天沒更新）----
  final oldest = i.oldestAssetUpdate;
  if (oldest != null) {
    final staleDay = startOfDay(oldest).add(const Duration(days: 3));
    var at = DateTime(staleDay.year, staleDay.month, staleDay.day, assetNotifyHour);
    if (!at.isAfter(i.now)) {
      // 已經過期：排在今天或明天晚上。
      at = DateTime(today.year, today.month, today.day, assetNotifyHour);
      if (!at.isAfter(i.now)) at = at.add(const Duration(days: 1));
    }
    if (at.isBefore(horizon)) {
      out.add(PlannedNotification(
        id: nextId++,
        at: at,
        title: '更新一下資產吧',
        body: '資產資訊超過 3 天沒更新了，更新後可以完成固定任務拿金幣。',
        kind: NotificationKind.asset,
      ));
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > maxPlannedNotifications
      ? out.sublist(0, maxPlannedNotifications)
      : out;
}
