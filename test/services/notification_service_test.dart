import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/notification_plan.dart';
import 'package:money_pet_app/services/notification_service.dart';

import '../helpers.dart';

void main() {
  test('從資料庫收集帳單、記帳狀態並排程', () async {
    final (s, _) = await makeServices(random: ScriptedRandom());
    final sched = NoopScheduler();
    final n = NotificationService(s, sched);

    expect(await n.plan(), isEmpty, reason: '還沒完成 Onboarding');

    await s.settings.update((x) => x.copyWith(onboardingDone: true));
    await s.pets.createPet(name: '小咪', type: PetType.cat);
    await s.bills.saveBill(
        name: '電費', type: BillType.utilities, amount: 800, dueDay: 15,
        remindDaysBefore: 3, recurrence: Recurrence.monthly, category: Category.home);

    expect(await n.reschedule(), greaterThan(0));
    expect(sched.scheduled.where((x) => x.kind == NotificationKind.bill).length, 2);
    final daily = sched.scheduled.where((x) => x.kind == NotificationKind.daily);
    expect(daily.first.at.day, 10, reason: '今天還沒記帳');

    await s.ledger.checkInNoSpend();
    await n.reschedule();
    expect(sched.scheduled.where((x) => x.kind == NotificationKind.daily).first.at.day, 11);

    await s.settings.update((x) => x.copyWith(notificationsEnabled: false));
    await n.reschedule();
    expect(sched.scheduled, isEmpty);
  });
}
