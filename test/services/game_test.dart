import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/data/models.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/shop_rules.dart';
import 'package:money_pet_app/domain/tasks.dart';
import 'package:money_pet_app/services/app_services.dart';
import 'package:money_pet_app/services/context.dart';
import 'package:money_pet_app/services/wallet_service.dart';

import '../helpers.dart';

void main() {
  late AppServices s;
  late FakeClock clock;

  setUp(() async {
    (s, clock) = await makeServices(random: ScriptedRandom());
    await s.pets.createPet(name: '阿狐', type: PetType.fox);
  });

  Future<void> giveCoins(int n) => s.ctx.db.transaction(
      (t) => s.wallet.addCoins(t, CoinSource.task, n, note: 'test'));

  group('寵物時間推進', () {
    test('同一天內不會重複扣', () async {
      expect(await s.pets.tick(), 0);
      clock.advance(const Duration(hours: 5));
      expect(await s.pets.tick(), 0);
    });

    test('隔 3 天補算 3 天', () async {
      clock.advance(const Duration(days: 3));
      expect(await s.pets.tick(), 3);
      final p = (await s.pets.activePet())!;
      expect(p.stats.fullness, 80 - 45);
      expect(p.stats.health, 80 - 15);
    });

    test('輕鬆模式', () async {
      await s.settings.update((x) => x.copyWith(easyMode: true));
      clock.advance(const Duration(days: 2));
      await s.pets.tick();
      expect((await s.pets.activePet())!.stats.fullness, 80 - 15);
    });

    test('戳戳：每天第一次心情 +2 並完成任務', () async {
      final a = await s.pets.poke();
      expect(a.firstToday, isTrue);
      final b = await s.pets.poke();
      expect(b.firstToday, isFalse);
      expect((await s.pets.activePet())!.stats.mood, 82);
    });
  });

  group('任務', () {
    test('建立寵物完成新手任務，可領一次', () async {
      final t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.createPet);
      expect(t.claimable, isTrue);
      await s.tasks.claim(t.def.id, t.period);
      expect(await s.wallet.coinBalance(), 50);
      await expectLater(() => s.tasks.claim(t.def.id, t.period), throwsA(isA<UserError>()));
    });

    test('未完成不能領', () async {
      await expectLater(() => s.tasks.claim(TaskIds.firstGoal, ''), throwsA(isA<UserError>()));
    });

    test('每日簽到隔天重置', () async {
      expect(await s.tasks.completeAndClaim(TaskIds.dailyCheckIn), isTrue);
      expect(await s.tasks.completeAndClaim(TaskIds.dailyCheckIn), isFalse);
      clock.advance(const Duration(days: 1));
      expect(await s.tasks.completeAndClaim(TaskIds.dailyCheckIn), isTrue);
      expect(await s.wallet.coinBalance(), 40);
    });

    test('累計記帳 7 天', () async {
      for (var i = 0; i < 6; i++) {
        await s.ledger.addExpense(category: Category.dining, amount: 100);
        clock.advance(const Duration(days: 1));
      }
      var t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.record7Days);
      expect(t.completed, isFalse);
      expect(t.hint, '6 / 7 天');
      await s.ledger.checkInNoSpend();
      t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.record7Days);
      expect(t.completed, isTrue);
    });

    test('道具獎勵進背包', () async {
      await s.ledger.addExpense(category: Category.dining, amount: 100);
      await s.tasks.claim(TaskIds.firstTransaction, '');
      expect(await s.inventory.quantityOf('cocoa'), greaterThanOrEqualTo(1));
    });

    test('資產更新固定任務：每 3 天一次', () async {
      await s.assets.addAccount('台新', AssetType.bank, 10000);
      var t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.assetUpdate);
      expect(t.completed, isTrue);
      await s.tasks.claim(t.def.id, t.period);

      clock.advance(const Duration(days: 1));
      final acc = (await s.assets.accounts()).single;
      await s.assets.updateBalance(acc.id, 12000);
      t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.assetUpdate);
      expect(t.completed, isFalse, reason: '才隔 1 天');

      clock.advance(const Duration(days: 2));
      await s.assets.updateBalance(acc.id, 13000);
      t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.assetUpdate);
      expect(t.completed, isTrue);
    });
  });

  group('商店', () {
    test('金幣不足不能買', () async {
      await expectLater(() => s.inventory.buy(0), throwsA(isA<UserError>()));
    });

    test('購買：扣金幣、進背包、每格每天一次', () async {
      await giveCoins(10000);
      final slot = dailyShop(clock.now).first;
      final item = await s.inventory.buy(0);
      expect(item.id, slot.item.id);
      expect(await s.wallet.coinBalance(), 10000 - slot.price);
      expect(await s.inventory.quantityOf(item.id), 1);
      await expectLater(() => s.inventory.buy(0), throwsA(isA<UserError>()));
      final states = await s.inventory.todayShop();
      expect(states.first.purchased, isTrue);
      final t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.firstShop);
      expect(t.completed, isTrue);
    });

    test('寵物失控時商店暫停營業', () async {
      await giveCoins(10000);
      await s.ctx.db.update('pet_status', {'is_insane': 1, 'san': 10});
      await expectLater(() => s.inventory.buy(0), throwsA(isA<UserError>()));
    });

    test('賣出道具換金幣', () async {
      await s.ctx.db.insert('inventory', {'item_id': 'unagi_don', 'quantity': 2});
      final got = await s.inventory.sell('unagi_don');
      expect(got, 66);
      expect(await s.inventory.quantityOf('unagi_don'), 1);
      await expectLater(() => s.inventory.sell('unagi_don', qty: 5), throwsA(isA<UserError>()));
    });

    test('使用道具', () async {
      await s.ctx.db.insert('inventory', {'item_id': 'onigiri', 'quantity': 1});
      final r = await s.pets.useItem('onigiri');
      expect(r.stats.fullness, 85);
      expect(await s.inventory.quantityOf('onigiri'), 0);
      await expectLater(() => s.pets.useItem('onigiri'), throwsA(isA<UserError>()));
    });
  });

  group('獎勵櫃 / PT 轉換', () {
    Future<void> givePt(int deci) async {
      // 先讀設定再開 transaction：transaction 裡用 ctx.db 會 deadlock。
      final rates = (await s.settings.load()).ptRates;
      await s.ctx.db.transaction((t) =>
          s.wallet.addPt(t, PtSource.goal, deci, period: '2026-05', rates: rates));
    }

    test('PT 不足不能兌換；足夠就扣 PT', () async {
      await s.rewards.addReward('吃大餐', 5000);
      final r = (await s.rewards.rewards()).single;
      await expectLater(() => s.rewards.redeem(r.id), throwsA(isA<UserError>()));
      await givePt(6000);
      await s.rewards.redeem(r.id);
      expect(await s.wallet.ptBalanceDeci(), 1000);
      expect((await s.rewards.rewards()).single.isRedeemed, isTrue);
      await expectLater(() => s.rewards.redeem(r.id), throwsA(isA<UserError>()));
    });

    test('PT → 金幣：1 PT = 10 金幣，單向', () async {
      await givePt(100); // 10 PT
      await s.wallet.convertPtToCoins(100);
      expect(await s.wallet.ptBalanceDeci(), 0);
      expect(await s.wallet.coinBalance(), 100);
      await expectLater(() => s.wallet.convertPtToCoins(1), throwsA(isA<UserError>()));
    });

    test('轉換金幣不會吃掉每月上限額度', () async {
      await givePt(100);
      await s.wallet.convertPtToCoins(100);
      expect(await s.wallet.cappedEarnedInPeriod('2026-05'), 0);
    });

    test('財務目標過期不能領', () async {
      await s.rewards.addGoal(name: '本週不喝飲料', ptRewardDeci: 300, deadline: DateTime(2026, 5, 12));
      clock.set(DateTime(2026, 5, 13, 9));
      final g = (await s.rewards.goals()).single;
      await expectLater(() => s.rewards.completeGoal(g.id), throwsA(isA<UserError>()));
    });
  });

  group('資產', () {
    test('淨資產 = 帳戶餘額 + 股票市值', () async {
      await s.assets.addAccount('台新', AssetType.bank, 50000);
      await s.assets.addAccount('永豐金', AssetType.securities, 2000);
      final sec = (await s.assets.accounts()).firstWhere((a) => a.type == AssetType.securities);
      await s.assets.upsertStock(accountId: sec.id, name: '台積電', code: '2330', quantity: 10, price: 1000);
      expect(await s.assets.netWorth(), 62000);
      final logs = await s.ctx.db.query('asset_log', where: 'account_id = ?', whereArgs: [sec.id]);
      expect(logs.last['balance_snapshot'], 12000);
    });
  });

  group('帳單', () {
    test('即將到期 → 一鍵記帳 → 換下一期', () async {
      await s.bills.saveBill(
        name: 'Netflix',
        type: BillType.subscription,
        amount: 390,
        dueDay: 12,
        remindDaysBefore: 3,
        recurrence: Recurrence.monthly,
        category: Category.subscription,
      );
      var soon = await s.bills.dueSoon();
      expect(soon.single.dueDate, DateTime(2026, 5, 12));
      final o = await s.bills.markPaid(soon.single, amount: 390);
      expect(o!.txn.amount, 390);
      expect(o.txn.note, 'Netflix');
      soon = await s.bills.dueSoon();
      expect(soon, isEmpty);
      final up = await s.bills.upcoming();
      expect(up.single.dueDate, DateTime(2026, 6, 12));
      await expectLater(() => s.bills.markPaid(BillDue(bill: up.single.bill, dueDate: DateTime(2026, 5, 12), isPaid: true), amount: 390),
          throwsA(isA<UserError>()));
    });

    test('逾期未繳仍會顯示', () async {
      await s.bills.saveBill(
        name: '電費',
        type: BillType.utilities,
        dueDay: 12,
        remindDaysBefore: 3,
        recurrence: Recurrence.monthly,
        category: Category.home,
      );
      clock.set(DateTime(2026, 5, 15, 9));
      final soon = await s.bills.dueSoon();
      expect(soon.single.dueDate, DateTime(2026, 5, 12));
    });

    test('信用卡額度警戒', () async {
      await s.bills.savePaymentMethod(
          name: '玉山 Pi 卡', type: PaymentType.creditCard, creditLimit: 10000, billingDay: 20, dueDay: 5);
      final card = (await s.bills.paymentMethods()).single;
      await s.ledger.addExpense(category: Category.clothing, amount: 8000, paymentMethodId: card.id);
      final usage = (await s.bills.paymentMethodUsage()).single;
      expect(usage.cycleSpent, 8000);
      expect(usage.warning, isTrue);
    });
  });

  test('清除所有資料', () async {
    await s.ledger.addExpense(category: Category.dining, amount: 100);
    await s.clearAllData();
    expect(await s.pets.activePet(), isNull);
    expect(await s.ledger.recentTransactions(), isEmpty);
    expect((await s.settings.load()).onboardingDone, isFalse);
  });
}
