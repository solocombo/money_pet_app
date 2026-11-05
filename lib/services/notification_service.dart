import '../domain/date_utils.dart';
import '../domain/notification_plan.dart';
import 'app_services.dart';

/// 平台通知的抽象。正式版用 flutter_local_notifications，測試用假的。
abstract class NotificationScheduler {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> replaceAll(List<PlannedNotification> list);
  Future<void> cancelAll();
}

/// 不做任何事（測試、或平台不支援時）。
class NoopScheduler implements NotificationScheduler {
  final List<PlannedNotification> scheduled = [];
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replaceAll(List<PlannedNotification> list) async =>
      scheduled
        ..clear()
        ..addAll(list);
  @override
  Future<void> cancelAll() async => scheduled.clear();
}

class NotificationService {
  NotificationService(this.services, this.scheduler);
  final AppServices services;
  final NotificationScheduler scheduler;

  /// 從資料庫收集資料並算出排程。
  Future<List<PlannedNotification>> plan() async {
    final s = await services.settings.load();
    if (!s.notificationsEnabled || !s.onboardingDone) return const [];
    final ctx = services.ctx;
    final pet = await services.pets.activePet();

    final bills = <BillForPlan>[];
    for (final b in await services.bills.bills()) {
      if (!b.isActive) continue;
      final paid = await ctx.db.query('bill_records',
          columns: ['due_date'], where: 'bill_id = ?', whereArgs: [b.id]);
      bills.add(BillForPlan(
        id: b.id,
        name: b.name,
        amount: b.amount,
        dueDay: b.dueDay,
        remindDaysBefore: b.remindDaysBefore,
        recurrence: b.recurrence,
        anchorMonth: b.anchorMonth,
        paidDueDates: {for (final r in paid) r['due_date'] as String},
      ));
    }

    final today = dateKey(ctx.now());
    final recorded = (await ctx.db.query('task_progress',
            where: 'task_id = ? AND period = ?',
            whereArgs: ['daily_record', today]))
        .isNotEmpty;

    return planNotifications(NotificationPlanInput(
      now: ctx.now(),
      petName: pet?.name ?? '寵物',
      dailyEnabled: s.dailyReminderEnabled,
      dailyTime: s.dailyReminderTime,
      recordedToday: recorded,
      bills: bills,
      oldestAssetUpdate: await services.assets.oldestUpdate(),
    ));
  }

  /// 重新排程（全部取消再排）。失敗不影響 APP 其他功能。
  Future<int> reschedule() async {
    try {
      final list = await plan();
      await scheduler.replaceAll(list);
      return list.length;
    } catch (_) {
      return -1;
    }
  }
}
