import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/items.dart';
import 'package:money_pet_app/domain/pet_rules.dart';

import '../helpers.dart';

PetStats full({double san = 80, int baseSan = 80}) => PetStats(
      fullness: 100,
      health: 100,
      cleanliness: 100,
      mood: 100,
      wisdom: 0,
      san: san,
      baseSan: baseSan,
    );

void main() {
  group('自然下降', () {
    test('一般速率', () {
      final s = tickDay(full(), const DayContext());
      expect(s.fullness, 85);
      expect(s.mood, 90);
      expect(s.cleanliness, 92);
      expect(s.health, 95);
      expect(s.wisdom, 0, reason: '智慧值不下降');
      expect(s.san, 80, reason: '沒有觸發條件時 San 不變');
    });

    test('本日無支出：飽食只降 7', () {
      final s = tickDay(full(), const DayContext(noSpendCheckIn: true));
      expect(s.fullness, 93);
      expect(s.mood, 90, reason: '其他屬性正常下降');
    });

    test('輕鬆模式：全部減半', () {
      final s = tickDay(full(), const DayContext(easyMode: true));
      expect(s.fullness, 92.5);
      expect(s.health, 97.5);
    });

    test('通用疲勞：×1.5', () {
      final s = tickDay(full(), const DayContext(conditions: {ConditionType.fatigue}));
      expect(s.fullness, 77.5);
    });

    test('過度放縱：心情下降加倍', () {
      final s = tickDay(full(), const DayContext(conditions: {ConditionType.overindulgence}));
      expect(s.mood, 80);
      expect(s.fullness, 85);
    });

    test('藥物依賴：健康上限 70', () {
      final s = tickDay(full(), const DayContext(conditions: {ConditionType.medicineDependence}));
      expect(s.health, 70);
    });

    test('屬性到 0 不會變負數', () {
      var s = full();
      for (var i = 0; i < 30; i++) {
        s = tickDay(s, const DayContext());
      }
      expect(s.fullness, 0);
      expect(s.health, 0);
      expect(s.san, greaterThanOrEqualTo(0));
    });
  });

  group('San 值', () {
    test('任一屬性低於 30 → -3', () {
      final s = tickDay(full().copyWith(fullness: 40), const DayContext());
      expect(s.fullness, 25);
      expect(s.san, 77);
    });

    test('生病 → -5', () {
      final s = tickDay(full(), const DayContext(conditions: {ConditionType.shopaholic}));
      expect(s.san, 75);
    });

    test('多條件同時觸發取最大值，不疊加', () {
      final s = tickDay(full().copyWith(fullness: 10),
          const DayContext(conditions: {ConditionType.shopaholic}));
      expect(s.san, 75, reason: 'max(3, 5) = 5');
    });

    test('低於 20 進入失控', () {
      final s = tickDay(full(san: 22), const DayContext(conditions: {ConditionType.fatigue}));
      expect(s.san, 17);
      expect(s.isInsane, isTrue);
    });

    test('失控時連續記帳 3 天恢復理智', () {
      var s = full(san: 10).copyWith(isInsane: true);
      s = tickDay(s, const DayContext(recorded: true));
      expect(s.insaneStreak, 1);
      s = tickDay(s, const DayContext(recorded: true));
      expect(s.isInsane, isTrue);
      s = tickDay(s, const DayContext(recorded: true));
      expect(s.isInsane, isFalse);
      expect(s.san, 40);
    });

    test('失控時中斷記帳，連續天數歸零', () {
      var s = full(san: 10).copyWith(isInsane: true);
      s = tickDay(s, const DayContext(recorded: true));
      s = tickDay(s, const DayContext(recorded: true));
      s = tickDay(s, const DayContext());
      expect(s.insaneStreak, 0);
      expect(s.isInsane, isTrue);
    });

    test('失控時屬性額外下降', () {
      final s = tickDay(full(san: 10).copyWith(isInsane: true), const DayContext(recorded: true));
      expect(s.fullness, 83);
    });

    test('San 上限隨智慧等級提升', () {
      expect(full(baseSan: 50).sanMax, 50);
      expect(full(baseSan: 50).copyWith(wisdom: 90).sanMax, 70);
      expect(full(baseSan: 80).copyWith(wisdom: 90).sanMax, 100);
      expect(full(baseSan: 100).copyWith(wisdom: 90).sanMax, 100, reason: '最高 100');
    });
  });

  group('智慧等級', () {
    test('分段', () {
      expect(wisdomLevelOf(0), 1);
      expect(wisdomLevelOf(20), 1);
      expect(wisdomLevelOf(21), 2);
      expect(wisdomLevelOf(60), 3);
      expect(wisdomLevelOf(61), 4);
      expect(wisdomLevelOf(100), 5);
    });
  });

  group('道具', () {
    final onigiri = itemById('onigiri')!;
    final soap = itemById('soap')!;

    test('一般使用', () {
      final r = applyItem(full().copyWith(fullness: 50), onigiri, const {});
      expect(r.stats.fullness, 55);
    });

    test('不超過 100', () {
      final r = applyItem(full(), onigiri, const {});
      expect(r.stats.fullness, 100);
    });

    test('腸胃炎：效果減半', () {
      final r = applyItem(full().copyWith(fullness: 50), onigiri, {ConditionType.gastroenteritis});
      expect(r.stats.fullness, 52.5);
    });

    test('購物狂：整潔道具不升反降', () {
      final r = applyItem(full().copyWith(cleanliness: 50), soap, {ConditionType.shopaholic});
      expect(r.stats.cleanliness, 45);
    });

    test('藥物依賴：健康上限 70', () {
      final elixir = itemById('elixir')!;
      final r = applyItem(full().copyWith(health: 60), elixir, {ConditionType.medicineDependence});
      expect(r.stats.health, 70);
    });

    test('理智道具不超過 San 上限', () {
      final charm = itemById('elder_charm')!;
      final r = applyItem(full(san: 70, baseSan: 80), charm, const {});
      expect(r.stats.san, 80);
    });

    test('理智回到 40 以上脫離失控', () {
      final tea = itemById('music_box')!; // +20
      final r = applyItem(full(san: 25).copyWith(isInsane: true), tea, const {});
      expect(r.stats.san, 45);
      expect(r.stats.isInsane, isFalse);
    });

    test('藥：沒生病時不生效', () {
      final med = itemById('cold_medicine')!;
      expect(applyItem(full(), med, const {}).curesConditions, isFalse);
      expect(applyItem(full(), med, {ConditionType.fatigue}).curesConditions, isTrue);
    });

    test('記帳加成與金額無關', () {
      final s = applyRecordBonus(full().copyWith(fullness: 50), Category.dining);
      expect(s.fullness, 53);
      final t = applyRecordBonus(full().copyWith(mood: 50), Category.publicTransport);
      expect(t.mood, 50, reason: '交通類沒有直接效果');
    });
  });

  group('San check', () {
    SanCheckInput input({
      int amount = 100,
      DateTime? at,
      int sameCat = 1,
      int? budget,
      int spent = 0,
    }) =>
        SanCheckInput(
          amount: amount,
          occurredAt: at ?? DateTime(2026, 5, 10, 12),
          sameCategoryCountToday: sameCat,
          impulseThreshold: 3000,
          repeatThreshold: 3,
          monthBudget: budget,
          monthSpentIncludingThis: spent,
        );

    test('一般消費不觸發', () {
      expect(sanTriggers(input()), isEmpty);
    });
    test('衝動消費', () {
      expect(sanTriggers(input(amount: 3001)), [SanTrigger.impulse]);
      expect(sanTriggers(input(amount: 3000)), isEmpty);
    });
    test('深夜記帳', () {
      expect(sanTriggers(input(at: DateTime(2026, 5, 10, 0, 30))), [SanTrigger.lateNight]);
      expect(sanTriggers(input(at: DateTime(2026, 5, 10, 23, 59))), isEmpty);
    });
    test('同類別當天超過 N 筆', () {
      expect(sanTriggers(input(sameCat: 4)), [SanTrigger.repeatedCategory]);
      expect(sanTriggers(input(sameCat: 3)), isEmpty);
    });
    test('月中預算快見底', () {
      expect(sanTriggers(input(budget: 10000, spent: 9500)), [SanTrigger.budgetRunningOut]);
      // 月底最後幾天不觸發
      expect(sanTriggers(input(at: DateTime(2026, 5, 28, 12), budget: 10000, spent: 9500)), isEmpty);
    });

    test('失敗機率隨智慧降低', () {
      expect(sanCheckFailChance(1), closeTo(0.5, 1e-9));
      expect(sanCheckFailChance(5), closeTo(0.3, 1e-9));
    });

    test('失敗 -10，可能進入失控', () {
      final r = runSanCheck(full(san: 25), [SanTrigger.impulse], ScriptedRandom(doubles: [0.1]));
      expect(r.failed, isTrue);
      expect(r.stats.san, 15);
      expect(r.stats.isInsane, isTrue);
    });

    test('通過不扣', () {
      final r = runSanCheck(full(san: 25), [SanTrigger.impulse], ScriptedRandom(doubles: [0.9]));
      expect(r.failed, isFalse);
      expect(r.stats.san, 25);
    });

    test('沒有觸發條件不擲骰', () {
      final r = runSanCheck(full(), const [], ScriptedRandom(doubles: [0.0]));
      expect(r.failed, isFalse);
    });
  });
}
