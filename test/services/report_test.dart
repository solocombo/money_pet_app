import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/services/report_service.dart';

import '../helpers.dart';

void main() {
  test('月報表', () async {
    final (s, clock) = await makeServices(random: ScriptedRandom());
    final r = ReportService(s.ctx);
    await s.bills.savePaymentMethod(name: 'Pi 卡', type: PaymentType.creditCard);
    final card = (await s.bills.paymentMethods()).single;
    await s.ledger.addExpense(category: Category.dining, amount: 300, occurredAt: DateTime(2026, 4, 3, 12));
    await s.ledger.addExpense(category: Category.dining, amount: 200, occurredAt: DateTime(2026, 5, 1, 12));
    await s.ledger.addExpense(category: Category.dining, amount: 100, savedAmount: 10, paymentMethodId: card.id,
        occurredAt: DateTime(2026, 5, 2, 12));
    await s.ledger.addExpense(category: Category.travel, amount: 1000, paymentMethodId: card.id, note: '墾丁',
        occurredAt: DateTime(2026, 5, 2, 13));
    await s.ledger.addIncome(category: IncomeCategory.salary, amount: 30000, occurredAt: DateTime(2026, 5, 5, 9));
    await s.ledger.checkInNoSpend(); // 5/10
    // 同一天有收入又按無支出，不重複算
    await s.ledger.addIncome(category: IncomeCategory.bonus, amount: 1);

    final m = await r.monthReport('2026-05');
    expect(m.expense, 1300);
    expect(m.income, 30001);
    expect(m.saved, 10);
    expect(m.prevExpense, 300);
    expect(m.changeVsPrev, closeTo(1300 / 300 - 1, 1e-9));
    expect(m.byGroup[CategoryGroup.food], 300);
    expect(m.byGroup[CategoryGroup.entertainment], 1000);
    expect(m.topCategories.first.category, Category.travel);
    expect(m.topCategories[1].count, 2);
    expect(m.byPayment.first.name, 'Pi 卡');
    expect(m.byPayment.first.amount, 1100);
    expect(m.byPayment.first.isCreditCard, isTrue);
    expect(m.byPayment[1].name, isNull);
    expect(m.trend.length, 6);
    expect(m.trend.last.month, '2026-05');
    expect(m.trend[4].expense, 300);
    expect(m.daysElapsed, 10);
    expect(m.dailyAverage, 130);
    expect(m.recordedDays, 4, reason: '5/1, 5/2, 5/5, 5/10');
    expect(m.noSpendDays, 1);
    expect(m.biggest!.$2, 1000);
    expect(m.biggest!.$3, '墾丁');

    clock.set(DateTime(2026, 6, 15));
    expect((await r.monthReport('2026-05')).daysElapsed, 31);
  });

  test('資產歷史', () async {
    final (s, clock) = await makeServices();
    final r = ReportService(s.ctx);
    await s.assets.addAccount('A', AssetType.bank, 1000);
    await s.assets.addAccount('B', AssetType.cash, 500);
    clock.advance(const Duration(days: 1));
    final a = (await s.assets.accounts()).firstWhere((x) => x.name == 'A');
    await s.assets.updateBalance(a.id, 2000);
    final h = await r.netWorthHistory();
    expect(h.map((e) => e.$2), [1500, 2500]);
  });
}
