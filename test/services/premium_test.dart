import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/items.dart';
import 'package:money_pet_app/domain/tasks.dart';
import 'package:money_pet_app/services/ad_reward_service.dart';

import '../helpers.dart';

void main() {
  test('進階版：無限重抽、簽到加碼道具', () async {
    final (s, _) = await makeServices(random: ScriptedRandom(ints: [0, 0, 0, 1, 0, 2, 0, 3, 0, 4]));
    await s.pets.createPet(name: '小咪', type: PetType.cat);
    expect(await s.premium.isPremium(), isFalse);
    ItemDef? bonus;
    await s.tasks.completeAndClaim(TaskIds.dailyCheckIn, onBonusItem: (i) => bonus = i);
    expect(bonus, isNull);

    await s.premium.unlock();
    expect(await s.premium.isPremium(), isTrue);
    final o = await s.ledger.addExpense(category: Category.dining, amount: 100);
    for (var i = 0; i < rerollDailyLimit + 3; i++) {
      await s.ads.reroll(o.txn.id);
    }
    expect(await s.ads.remaining(AdRewardKind.reroll), AdRewardService.unlimited);
    expect(await s.ads.remaining(AdRewardKind.coins), adCoinDailyLimit, reason: '金幣仍是每天 5 次');
  });

  test('進階版簽到送道具', () async {
    final (s, clock) = await makeServices(random: ScriptedRandom());
    await s.premium.unlock();
    ItemDef? bonus;
    expect(await s.tasks.completeAndClaim(TaskIds.dailyCheckIn, onBonusItem: (i) => bonus = i), isTrue);
    expect(bonus, isNotNull);
    expect(await s.inventory.quantityOf(bonus!.id), 1);
  });
}
