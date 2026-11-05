import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/services/ad_reward_service.dart';
import 'package:money_pet_app/services/context.dart';

import '../helpers.dart';

void main() {
  test('看廣告領金幣：每天 5 次，隔天重置', () async {
    final (s, clock) = await makeServices();
    for (var i = 0; i < adCoinDailyLimit; i++) {
      await s.ads.claimCoins();
    }
    expect(await s.wallet.coinBalance(), adCoinReward * adCoinDailyLimit);
    expect(await s.ads.remaining(AdRewardKind.coins), 0);
    await expectLater(() => s.ads.claimCoins(), throwsA(isA<UserError>()));
    clock.advance(const Duration(days: 1));
    expect(await s.ads.remaining(AdRewardKind.coins), adCoinDailyLimit);
    await s.ads.claimCoins();
    final keys = await s.ctx.db.query('app_settings', where: "key LIKE 'ad_coins:%'");
    expect(keys.length, 1, reason: '舊計數器清掉');
  });

  test('重抽：換掉道具、每天 2 次、道具用掉或隔天就不能重抽', () async {
    // nextInt 依序：第一次掉落 0（普通第一個 onigiri），重抽時 rarity 0 → 普通第 2 個
    final (s, clock) = await makeServices(random: ScriptedRandom(ints: [0, 0, 0, 1, 0, 2, 0, 0]));
    await s.pets.createPet(name: '小咪', type: PetType.cat);
    final o = await s.ledger.addExpense(category: Category.dining, amount: 100);
    final first = o.droppedItem!.id;
    expect(await s.ads.canReroll(o.txn.id), isTrue);
    final next = await s.ads.reroll(o.txn.id);
    expect(next.id, isNot(first));
    expect(await s.inventory.quantityOf(first), 0);
    expect(await s.inventory.quantityOf(next.id), 1);
    expect((await s.ledger.recentTransactions()).single.droppedItemId, next.id);

    // 刪除交易時收回的是新道具
    await s.ads.reroll(o.txn.id);
    expect(await s.ads.canReroll(o.txn.id), isFalse, reason: '次數用完');
    await expectLater(() => s.ads.reroll(o.txn.id), throwsA(isA<UserError>()));

    clock.advance(const Duration(days: 1));
    expect(await s.ads.canReroll(o.txn.id), isFalse, reason: '不是今天的');
    final o2 = await s.ledger.addExpense(category: Category.dining, amount: 100);
    await s.ctx.db.delete('inventory');
    expect(await s.ads.canReroll(o2.txn.id), isFalse, reason: '道具已用掉');
  });
}
