import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/items.dart';
import 'package:money_pet_app/domain/pet_rules.dart';
import 'package:money_pet_app/domain/recipes.dart';
import 'package:money_pet_app/domain/shop_rules.dart';
import 'package:money_pet_app/domain/tasks.dart';
import 'package:money_pet_app/services/context.dart';

import '../helpers.dart';

void main() {
  group('配方定義', () {
    test('每個配方的材料與成品都存在，成品只能合成', () {
      for (final r in recipes) {
        expect(r.result.craftedOnly, isTrue, reason: r.id);
        for (final id in r.ingredients.keys) {
          expect(itemById(id), isNotNull, reason: '${r.id}: $id');
          expect(itemById(id)!.craftedOnly, isFalse);
        }
      }
    });
    test('成品不會掉落、商店不賣', () {
      final rng = Random(1);
      for (var i = 0; i < 5000; i++) {
        expect(rollItemDrop(rng).craftedOnly, isFalse);
      }
      for (var d = 1; d <= 90; d++) {
        expect(dailyShop(DateTime(2026, 1, d)).any((s) => s.item.craftedOnly), isFalse);
      }
    });
    test('可合成份數', () {
      final r = recipes.firstWhere((r) => r.id == 'r_bento');
      expect(craftableCount(r, {'onigiri': 5, 'vitamin': 1}), 1);
      expect(craftableCount(r, {'onigiri': 4, 'vitamin': 3}), 2);
      expect(craftableCount(r, {'onigiri': 1, 'vitamin': 3}), 0);
    });
    test('多重效果道具', () {
      final feast = itemById('feast')!;
      const s = PetStats(fullness: 10, health: 10, cleanliness: 10, mood: 10, wisdom: 0, san: 50, baseSan: 50);
      final r = applyItem(s, feast, const {});
      expect(r.stats.fullness, 40);
      expect(r.stats.health, 30);
      expect(r.stats.mood, 30);
      expect(r.stats.cleanliness, 20);
      expect(feast.effectText, '飽食 +30、健康 +20、心情 +20、整潔 +10');
    });
  });

  group('合成', () {
    test('扣材料、得成品、完成新手任務', () async {
      final (s, _) = await makeServices();
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      await s.ctx.db.insert('inventory', {'item_id': 'onigiri', 'quantity': 3});
      await s.ctx.db.insert('inventory', {'item_id': 'vitamin', 'quantity': 1});
      final item = await s.inventory.craft('r_bento');
      expect(item.id, 'bento');
      expect(await s.inventory.quantityOf('onigiri'), 1);
      expect(await s.inventory.quantityOf('vitamin'), 0);
      expect(await s.inventory.quantityOf('bento'), 1);
      expect((await s.inventory.collection()).containsKey('bento'), isTrue);
      final t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.firstCraft);
      expect(t.completed, isTrue);
      await expectLater(() => s.inventory.craft('r_bento'), throwsA(isA<UserError>()));
      expect(await s.inventory.quantityOf('onigiri'), 1, reason: '失敗不扣材料');
    });

    test('智慧等級不夠不能做特殊配方', () async {
      final (s, _) = await makeServices();
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      for (final id in ['unagi_don', 'chicken_soup', 'game_console']) {
        await s.ctx.db.insert('inventory', {'item_id': id, 'quantity': 1});
      }
      await expectLater(() => s.inventory.craft('r_feast'), throwsA(isA<UserError>()));
      await s.ctx.db.update('pet_status', {'wisdom': 70});
      expect((await s.inventory.craft('r_feast')).id, 'feast');
    });

    test('失控時不能合成', () async {
      final (s, _) = await makeServices();
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      await s.ctx.db.insert('inventory', {'item_id': 'sticky_note', 'quantity': 3});
      await s.ctx.db.update('pet_status', {'is_insane': 1, 'san': 5});
      await expectLater(() => s.inventory.craft('r_study_plan'), throwsA(isA<UserError>()));
    });
  });

  group('里程碑', () {
    test('連續記帳 7 天；中斷後重新計算', () async {
      final (s, clock) = await makeServices(random: ScriptedRandom());
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      for (var i = 0; i < 3; i++) {
        await s.ledger.checkInNoSpend();
        clock.advance(const Duration(days: 1));
      }
      clock.advance(const Duration(days: 1)); // 中斷一天
      for (var i = 0; i < 6; i++) {
        await s.ledger.addExpense(category: Category.dining, amount: 50);
        clock.advance(const Duration(days: 1));
      }
      expect(await s.tasks.currentStreak(), 6, reason: '今天還沒記，從昨天往回算');
      var t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.streak7);
      expect(t.completed, isFalse);
      expect(t.hint, '目前連續 6 天');
      await s.ledger.checkInNoSpend();
      t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.streak7);
      expect(t.completed, isTrue);
    });

    test('第一次兌換獎勵', () async {
      final (s, _) = await makeServices();
      await s.rewards.addReward('小點心', 10);
      await s.ctx.db.insert('pt_log', {'source': 'goal', 'amount': 10, 'period': '2026-05', 'created_at': 0});
      await s.rewards.redeem((await s.rewards.rewards()).single.id);
      final t = (await s.tasks.statuses()).firstWhere((t) => t.def.id == TaskIds.firstRedeem);
      expect(t.claimable, isTrue);
      await s.tasks.claim(t.def.id, t.period);
      expect(await s.inventory.quantityOf('star_projector'), 1);
    });
  });
}
