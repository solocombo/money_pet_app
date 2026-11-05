import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/pet_rules.dart';
import 'package:money_pet_app/domain/pt_rules.dart';
import 'package:money_pet_app/domain/tasks.dart';
import 'package:money_pet_app/services/app_services.dart';
import 'package:money_pet_app/services/context.dart';

import '../helpers.dart';

void main() {
  late AppServices s;
  late FakeClock clock;

  setUp(() async {
    // nextDouble 0.99 → San check 永遠通過；nextInt 0 → 掉落永遠是普通級第一個。
    (s, clock) = await makeServices(random: ScriptedRandom());
    await s.pets.createPet(name: '小咪', type: PetType.cat);
  });

  group('PT：沒有預算', () {
    test('只拿道具，不拿 PT', () async {
      final o = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 30000);
      expect(o.noBudget, isTrue);
      expect(o.ptAwardedDeci, 0);
      expect(o.droppedItem, isNotNull);
      expect(await s.wallet.ptBalanceDeci(), 0);
    });
  });

  group('PT：有預算', () {
    setUp(() async {
      await s.ledger.setBudget('2026-05', null, 20000);
    });

    test('收入 × 0.01', () async {
      final o = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 30000);
      expect(o.ptAwardedDeci, 3000);
      expect(await s.wallet.ptBalanceDeci(), 3000);
    });

    test('省下金額 × 0.1', () async {
      final o = await s.ledger.addExpense(
          category: Category.dining, amount: 500, savedAmount: 50);
      expect(o.ptAwardedDeci, 50);
    });

    test('省下金額超過消費金額 → 拒絕', () async {
      expect(
        () => s.ledger.addExpense(category: Category.dining, amount: 100, savedAmount: 101),
        throwsA(isA<UserError>()),
      );
    });

    test('每月上限', () async {
      await s.settings.update((x) => x.copyWith(
          ptRates: x.ptRates.copyWith(monthlyCapDeci: 1000))); // 100 PT
      final a = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 60000); // 600 PT
      expect(a.ptAwardedDeci, 1000);
      expect(a.ptCapped, isTrue);
      final b = await s.ledger.addIncome(category: IncomeCategory.bonus, amount: 1000);
      expect(b.ptAwardedDeci, 0);
      expect(await s.wallet.ptBalanceDeci(), 1000);
    });

    test('財務目標不受上限影響', () async {
      await s.settings.update((x) => x.copyWith(
          ptRates: x.ptRates.copyWith(monthlyCapDeci: 10)));
      await s.ledger.addIncome(category: IncomeCategory.salary, amount: 60000);
      await s.rewards.addGoal(
          name: '帶便當三次', ptRewardDeci: 500, deadline: DateTime(2026, 5, 31));
      final g = (await s.rewards.goals()).single;
      expect(await s.rewards.completeGoal(g.id), 500);
      expect(await s.wallet.ptBalanceDeci(), 510);
    });

    test('補記上個月的帳不給 PT', () async {
      await s.ledger.setBudget('2026-04', null, 20000);
      final o = await s.ledger.addIncome(
          category: IncomeCategory.salary,
          amount: 30000,
          occurredAt: DateTime(2026, 4, 20));
      expect(o.pastMonth, isTrue);
      expect(o.ptAwardedDeci, 0);
    });

    test('刪除交易會退回 PT，額度也回補', () async {
      await s.settings.update((x) => x.copyWith(
          ptRates: x.ptRates.copyWith(monthlyCapDeci: 1000)));
      final o = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 60000);
      await s.ledger.deleteTransaction(o.txn.id);
      expect(await s.wallet.ptBalanceDeci(), 0);
      expect(await s.wallet.cappedEarnedInPeriod('2026-05'), 0);
      final again = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 10000);
      expect(again.ptAwardedDeci, 1000);
    });
  });

  group('道具', () {
    test('刪除交易收回掉落的道具', () async {
      final o = await s.ledger.addExpense(category: Category.dining, amount: 100);
      final id = o.droppedItem!.id;
      expect(await s.inventory.quantityOf(id), 1);
      await s.ledger.deleteTransaction(o.txn.id);
      expect(await s.inventory.quantityOf(id), 0);
      expect((await s.inventory.collection()).containsKey(id), isTrue,
          reason: '圖鑑紀錄保留');
    });

    test('每日掉落上限，刪除重記也不會重置', () async {
      await s.settings.update((x) => x.copyWith(dailyDropLimit: 2));
      final a = await s.ledger.addExpense(category: Category.dining, amount: 100);
      await s.ledger.deleteTransaction(a.txn.id);
      await s.ledger.addExpense(category: Category.dining, amount: 100);
      final c = await s.ledger.addExpense(category: Category.dining, amount: 100);
      expect(c.droppedItem, isNull);
      expect(c.dropLimitReached, isTrue);

      clock.advance(const Duration(days: 1));
      final d = await s.ledger.addExpense(category: Category.dining, amount: 100);
      expect(d.droppedItem, isNotNull, reason: '隔天重置');
    });
  });

  group('本日無支出', () {
    test('打卡給金幣、完成每日記帳任務', () async {
      await s.ledger.checkInNoSpend();
      expect(await s.wallet.coinBalance(), noSpendCoinReward);
      final t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.dailyRecord);
      expect(t.completed, isTrue);
    });

    test('已有支出不能打卡', () async {
      await s.ledger.addExpense(category: Category.dining, amount: 100);
      expect(() => s.ledger.checkInNoSpend(), throwsA(isA<UserError>()));
    });

    test('同一天不能打卡兩次', () async {
      await s.ledger.checkInNoSpend();
      expect(() => s.ledger.checkInNoSpend(), throwsA(isA<UserError>()));
    });

    test('打卡後又記支出 → 取消打卡並收回金幣', () async {
      await s.ledger.checkInNoSpend();
      final o = await s.ledger.addExpense(category: Category.dining, amount: 100);
      expect(o.cancelledNoSpend, isTrue);
      expect(await s.ledger.isNoSpendToday(), isFalse);
      expect(await s.wallet.coinBalance(), 0);
    });

    test('收入不會取消打卡', () async {
      await s.ledger.checkInNoSpend();
      final o = await s.ledger.addIncome(category: IncomeCategory.salary, amount: 100);
      expect(o.cancelledNoSpend, isFalse);
      expect(await s.ledger.isNoSpendToday(), isTrue);
    });

    test('飽食值當天只降 7', () async {
      await s.ledger.checkInNoSpend();
      final before = (await s.pets.activePet())!.stats.fullness;
      clock.advance(const Duration(days: 1));
      await s.pets.tick();
      expect((await s.pets.activePet())!.stats.fullness, before - 7);
    });
  });

  group('超支生病', () {
    test('單一類別超過 20% → 對應生病，同月只觸發一次', () async {
      await s.ledger.setBudget('2026-05', CategoryGroup.food, 1000);
      final a = await s.ledger.addExpense(category: Category.dining, amount: 1200);
      expect(a.newCondition, isNull);
      final b = await s.ledger.addExpense(category: Category.drinks, amount: 1);
      expect(b.newCondition, ConditionType.gastroenteritis);
      final c = await s.ledger.addExpense(category: Category.groceries, amount: 500);
      expect(c.newCondition, isNull);
      expect((await s.pets.activeConditions()).length, 1);
    });

    test('生病 5 天後自動康復', () async {
      await s.ledger.setBudget('2026-05', CategoryGroup.living, 100);
      await s.ledger.addExpense(category: Category.clothing, amount: 1000);
      expect(await s.pets.activeConditions(), isNotEmpty);
      clock.advance(const Duration(days: 5, minutes: 1));
      expect(await s.pets.activeConditions(), isEmpty);
    });

    test('用藥治療', () async {
      await s.ledger.setBudget('2026-05', CategoryGroup.living, 100);
      await s.ledger.addExpense(category: Category.clothing, amount: 1000);
      await s.tasks.claim(TaskIds.firstTransaction, ''); // 獎勵：熱可可
      // 直接放一顆藥
      await s.ctx.db.insert('inventory', {'item_id': 'cold_medicine', 'quantity': 1});
      final r = await s.pets.useItem('cold_medicine');
      expect(r.curesConditions, isTrue);
      expect(await s.pets.activeConditions(), isEmpty);
      expect(await s.inventory.quantityOf('cold_medicine'), 0);
    });

    test('沒生病時用藥不會消耗', () async {
      await s.ctx.db.insert('inventory', {'item_id': 'cold_medicine', 'quantity': 1});
      await s.pets.useItem('cold_medicine');
      expect(await s.inventory.quantityOf('cold_medicine'), 1);
    });
  });

  group('月結算', () {
    test('上個月省下的錢在新月份第一次開啟時結算', () async {
      await s.ledger.setBudget('2026-05', null, 10000);
      await s.ledger.setBudget('2026-05', CategoryGroup.food, 3000);
      await s.ledger.addExpense(category: Category.dining, amount: 2000);
      await s.ledger.addExpense(category: Category.leisure, amount: 1000);

      clock.set(DateTime(2026, 6, 1, 9));
      final report = await s.onAppResume();
      expect(report.settlements.length, 1);
      final (month, result, awarded) = report.settlements.single;
      expect(month, '2026-05');
      // 類別：3000-2000=1000 → 100 PT；總額：10000-3000=7000 → 700 PT
      expect(result.grossPtDeci, 8000);
      expect(awarded, 8000);
      expect(report.budgetsCarriedOver, isTrue);

      // 不會重複結算
      final again = await s.onAppResume();
      expect(again.settlements, isEmpty);
    });

    test('結算 PT 計入該月上限', () async {
      await s.settings.update((x) => x.copyWith(
          ptRates: x.ptRates.copyWith(monthlyCapDeci: 5000)));
      await s.ledger.setBudget('2026-05', null, 100000);
      await s.ledger.addIncome(category: IncomeCategory.salary, amount: 40000); // 400 PT
      clock.set(DateTime(2026, 6, 1, 9));
      final report = await s.onAppResume();
      expect(report.settlements.single.$3, 1000, reason: '上限 500 PT，已拿 400');
    });

    test('沿用上個月預算', () async {
      await s.ledger.setBudget('2026-05', null, 10000);
      await s.ledger.setBudget('2026-05', CategoryGroup.food, 3000);
      clock.set(DateTime(2026, 6, 2));
      await s.onAppResume();
      final b = await s.ledger.budgetsFor('2026-06');
      expect(b.total, 10000);
      expect(b.groups[CategoryGroup.food], 3000);
    });
  });

  group('San check 整合', () {
    test('深夜衝動消費失敗 → San -10', () async {
      final (s2, _) = await makeServices(
        start: DateTime(2026, 5, 10, 1),
        random: ScriptedRandom(doubles: [0.0]),
      );
      await s2.pets.createPet(name: '小鳥', type: PetType.bird); // San 50
      final o = await s2.ledger.addExpense(category: Category.leisure, amount: 5000);
      expect(o.sanTriggers, containsAll([SanTrigger.impulse, SanTrigger.lateNight]));
      expect(o.sanCheckFailed, isTrue);
      expect((await s2.pets.activePet())!.stats.san, 40, reason: '多個條件只扣一次');
    });

    test('關閉 San check 就不觸發', () async {
      await s.settings.update((x) => x.copyWith(disableSanCheck: true));
      final o = await s.ledger.addExpense(category: Category.leisure, amount: 99999);
      expect(o.sanTriggers, isEmpty);
    });
  });

  test('不能記未來的帳', () async {
    expect(
      () => s.ledger.addExpense(
          category: Category.dining, amount: 1, occurredAt: DateTime(2026, 5, 11)),
      throwsA(isA<UserError>()),
    );
  });

  test('PT 顯示格式', () {
    expect(formatPt(3000), '300.0');
  });
}
