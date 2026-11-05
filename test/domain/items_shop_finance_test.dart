import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/date_utils.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/finance_rules.dart';
import 'package:money_pet_app/domain/items.dart';
import 'package:money_pet_app/domain/shop_rules.dart';

void main() {
  group('道具目錄', () {
    test('id 不重複', () {
      final ids = itemCatalog.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
    });
    test('每種稀有度都有道具可以掉', () {
      for (final r in Rarity.values) {
        expect(itemCatalog.where((i) => i.rarity == r), isNotEmpty, reason: r.name);
      }
    });
    test('掉落權重加總 100', () {
      expect(Rarity.values.fold<int>(0, (s, r) => s + r.dropWeight), 100);
    });
  });

  test('稀有度掉落分佈接近 60/25/12/3', () {
    final rng = Random(7);
    final counts = <Rarity, int>{};
    const n = 100000;
    for (var i = 0; i < n; i++) {
      final r = rollRarity(rng);
      counts[r] = (counts[r] ?? 0) + 1;
    }
    for (final r in Rarity.values) {
      expect(counts[r]! / n * 100, closeTo(r.dropWeight, 1.0), reason: r.name);
    }
  });

  group('每日商店', () {
    test('同一天結果固定', () {
      final a = dailyShop(DateTime(2026, 5, 10, 8));
      final b = dailyShop(DateTime(2026, 5, 10, 22));
      expect(a.map((s) => s.item.id), b.map((s) => s.item.id));
    });
    test('4 格、不重複、最後一格是限定', () {
      for (var d = 1; d <= 60; d++) {
        final shop = dailyShop(DateTime(2026, 1, d));
        expect(shop.length, 4);
        expect(shop.map((s) => s.item.id).toSet().length, 4);
        expect(shop.last.isLimited, isTrue);
        expect(shop.last.item.rarity.index, greaterThanOrEqualTo(Rarity.epic.index));
        expect(shop.last.price, lessThan(shop.last.item.shopPrice));
        expect(shop.take(3).any((s) => s.item.rarity == Rarity.legendary), isFalse);
      }
    });
  });

  group('帳單到期日', () {
    test('每月：本月還沒到', () {
      expect(
          nextDueDate(today: DateTime(2026, 5, 10), dueDay: 15, recurrence: Recurrence.monthly),
          DateTime(2026, 5, 15));
    });
    test('每月：本月已過 → 下個月', () {
      expect(
          nextDueDate(today: DateTime(2026, 5, 20), dueDay: 15, recurrence: Recurrence.monthly),
          DateTime(2026, 6, 15));
    });
    test('當天到期算今天', () {
      expect(
          nextDueDate(today: DateTime(2026, 5, 15, 18), dueDay: 15, recurrence: Recurrence.monthly),
          DateTime(2026, 5, 15));
    });
    test('31 號在小月 → 月底', () {
      expect(
          nextDueDate(today: DateTime(2026, 2, 1), dueDay: 31, recurrence: Recurrence.monthly),
          DateTime(2026, 2, 28));
    });
    test('跨年', () {
      expect(
          nextDueDate(today: DateTime(2026, 12, 20), dueDay: 5, recurrence: Recurrence.monthly),
          DateTime(2027, 1, 5));
    });
    test('每季：從起算月每 3 個月', () {
      expect(
          nextDueDate(
              today: DateTime(2026, 5, 10),
              dueDay: 1,
              recurrence: Recurrence.quarterly,
              anchorMonth: '2026-01'),
          DateTime(2026, 7, 1));
    });
    test('每年', () {
      expect(
          nextDueDate(
              today: DateTime(2026, 5, 10),
              dueDay: 20,
              recurrence: Recurrence.yearly,
              anchorMonth: '2025-03'),
          DateTime(2027, 3, 20));
    });
    test('提醒區間', () {
      expect(isBillInReminderWindow(today: DateTime(2026, 5, 12), dueDate: DateTime(2026, 5, 15), remindDaysBefore: 3), isTrue);
      expect(isBillInReminderWindow(today: DateTime(2026, 5, 11), dueDate: DateTime(2026, 5, 15), remindDaysBefore: 3), isFalse);
      expect(isBillInReminderWindow(today: DateTime(2026, 5, 16), dueDate: DateTime(2026, 5, 15), remindDaysBefore: 3), isFalse);
    });
  });

  group('信用卡', () {
    test('帳單週期', () {
      final (s, e) = creditCardCycle(DateTime(2026, 5, 10), 20);
      expect(s, DateTime(2026, 4, 21));
      expect(e, DateTime(2026, 5, 21));
      final (s2, e2) = creditCardCycle(DateTime(2026, 5, 25), 20);
      expect(s2, DateTime(2026, 5, 21));
      expect(e2, DateTime(2026, 6, 21));
    });
    test('12 月跨年週期', () {
      final (s, e) = creditCardCycle(DateTime(2026, 12, 28), 25);
      expect(s, DateTime(2026, 12, 26));
      expect(e, DateTime(2027, 1, 26));
    });
    test('80% 警戒', () {
      expect(isCreditWarning(spent: 79999, creditLimit: 100000, warnRatio: 0.8), isFalse);
      expect(isCreditWarning(spent: 80000, creditLimit: 100000, warnRatio: 0.8), isTrue);
      expect(isCreditWarning(spent: 80000, creditLimit: 0, warnRatio: 0.8), isFalse);
    });
  });

  group('日期工具', () {
    test('key 轉換', () {
      expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(monthKey(DateTime(2026, 12, 31)), '2026-12');
      expect(previousMonthKey('2026-01'), '2025-12');
      expect(nextMonthKey('2026-12'), '2027-01');
    });
    test('資產三天沒更新', () {
      final now = DateTime(2026, 5, 10, 9);
      expect(isAssetStale(DateTime(2026, 5, 8, 23), now), isFalse);
      expect(isAssetStale(DateTime(2026, 5, 7, 1), now), isTrue);
      expect(isAssetStale(null, now), isTrue);
    });
    test('金額格式', () {
      expect(formatMoney(1234567), '\$1,234,567');
      expect(formatMoney(0), '\$0');
      expect(formatMoney(-500), '-\$500');
    });
  });
}
