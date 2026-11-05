import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/notification_plan.dart';

NotificationPlanInput input({
  DateTime? now,
  bool daily = true,
  String time = '21:00',
  bool recorded = false,
  List<BillForPlan> bills = const [],
  DateTime? asset,
}) =>
    NotificationPlanInput(
      now: now ?? DateTime(2026, 5, 10, 12),
      petName: '小狐',
      dailyEnabled: daily,
      dailyTime: time,
      recordedToday: recorded,
      bills: bills,
      oldestAssetUpdate: asset,
    );

BillForPlan bill({int dueDay = 15, int remind = 3, Set<String> paid = const {}}) => BillForPlan(
      id: 'b',
      name: 'Netflix',
      amount: 390,
      dueDay: dueDay,
      remindDaysBefore: remind,
      recurrence: Recurrence.monthly,
      anchorMonth: '2026-05',
      paidDueDates: paid,
    );

List<PlannedNotification> ofKind(List<PlannedNotification> l, NotificationKind k) =>
    l.where((n) => n.kind == k).toList();

void main() {
  group('每日提醒', () {
    test('排 14 天，從今天 21:00 開始', () {
      final d = ofKind(planNotifications(input()), NotificationKind.daily);
      expect(d.length, 14);
      expect(d.first.at, DateTime(2026, 5, 10, 21));
      expect(d.first.title, contains('小狐'));
    });
    test('今天已記帳就跳過今天', () {
      final d = ofKind(planNotifications(input(recorded: true)), NotificationKind.daily);
      expect(d.first.at, DateTime(2026, 5, 11, 21));
    });
    test('今天的時間已經過了就跳過', () {
      final d = ofKind(planNotifications(input(now: DateTime(2026, 5, 10, 22))), NotificationKind.daily);
      expect(d.first.at, DateTime(2026, 5, 11, 21));
    });
    test('關閉就不排', () {
      expect(ofKind(planNotifications(input(daily: false)), NotificationKind.daily), isEmpty);
    });
  });

  group('帳單', () {
    test('到期前 N 天 + 到期當天各一則', () {
      final b = ofKind(planNotifications(input(bills: [bill()])), NotificationKind.bill);
      expect(b.map((n) => n.at), [DateTime(2026, 5, 12, 9), DateTime(2026, 5, 15, 9)]);
      expect(b.first.body, contains('\$390'));
    });
    test('已繳的那期不提醒', () {
      final b = ofKind(planNotifications(input(bills: [bill(paid: {'2026-05-15'})])), NotificationKind.bill);
      expect(b, isEmpty);
    });
    test('提醒時間已過只排到期日', () {
      final b = ofKind(
          planNotifications(input(now: DateTime(2026, 5, 13, 12), bills: [bill()])), NotificationKind.bill);
      expect(b.map((n) => n.at), [DateTime(2026, 5, 15, 9)]);
    });
    test('下一期在範圍內也會排', () {
      final b = ofKind(
          planNotifications(input(now: DateTime(2026, 5, 20, 12), bills: [bill(dueDay: 25)])),
          NotificationKind.bill);
      expect(b.map((n) => n.at), [DateTime(2026, 5, 22, 9), DateTime(2026, 5, 25, 9)]);
    });
  });

  group('資產', () {
    test('最後更新 + 3 天晚上提醒', () {
      final a = ofKind(planNotifications(input(asset: DateTime(2026, 5, 9, 8))), NotificationKind.asset);
      expect(a.single.at, DateTime(2026, 5, 12, 20));
    });
    test('早就過期：今晚提醒', () {
      final a = ofKind(planNotifications(input(asset: DateTime(2026, 4, 1))), NotificationKind.asset);
      expect(a.single.at, DateTime(2026, 5, 10, 20));
    });
    test('沒有資產帳戶不提醒', () {
      expect(ofKind(planNotifications(input()), NotificationKind.asset), isEmpty);
    });
  });

  test('依時間排序、id 不重複', () {
    final l = planNotifications(input(bills: [bill()], asset: DateTime(2026, 5, 1)));
    for (var i = 1; i < l.length; i++) {
      expect(l[i].at.isBefore(l[i - 1].at), isFalse);
    }
    expect(l.map((n) => n.id).toSet().length, l.length);
  });
}
