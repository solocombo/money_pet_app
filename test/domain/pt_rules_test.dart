import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/pt_rules.dart';

void main() {
  group('ptFromAmount', () {
    test('省下金額 × 0.1，保留小數一位', () {
      expect(ptFromAmount(123, 0.1), 123); // 12.3 PT
      expect(ptFromAmount(7, 0.1), 7); // 0.7 PT，不能因浮點誤差變 0.6
      expect(ptFromAmount(1, 0.1), 1);
    });

    test('收入 × 0.01，小數第二位捨去', () {
      expect(ptFromAmount(30000, 0.01), 3000); // 300.0 PT
      expect(ptFromAmount(155, 0.01), 15); // 1.55 → 1.5
      expect(ptFromAmount(9, 0.01), 0); // 0.09 → 0.0
    });

    test('0 或負數不給 PT', () {
      expect(ptFromAmount(0, 0.1), 0);
      expect(ptFromAmount(-50, 0.1), 0);
      expect(ptFromAmount(100, 0), 0);
    });
  });

  group('每月上限', () {
    test('還有額度：全給', () {
      expect(applyMonthlyCap(requestedDeci: 50, alreadyEarnedDeci: 100, capDeci: 1000), 50);
    });
    test('額度不夠：只給剩下的', () {
      expect(applyMonthlyCap(requestedDeci: 500, alreadyEarnedDeci: 800, capDeci: 1000), 200);
    });
    test('額度用完：0', () {
      expect(applyMonthlyCap(requestedDeci: 500, alreadyEarnedDeci: 1000, capDeci: 1000), 0);
      expect(applyMonthlyCap(requestedDeci: 500, alreadyEarnedDeci: 1200, capDeci: 1000), 0);
    });
    test('cap = 0 代表不設上限', () {
      expect(applyMonthlyCap(requestedDeci: 99999, alreadyEarnedDeci: 99999, capDeci: 0), 99999);
    });
  });

  group('省下金額驗證', () {
    test('不能超過消費金額', () {
      expect(validateSavedAmount(amount: 100, saved: 101), isNotNull);
      expect(validateSavedAmount(amount: 100, saved: 100), isNull);
      expect(validateSavedAmount(amount: 100, saved: 0), isNull);
    });
    test('不能是負數', () {
      expect(validateSavedAmount(amount: 100, saved: -1), isNotNull);
    });
  });

  group('超支判定', () {
    test('超過預算 20% 才算超支', () {
      expect(isOverspent(budget: 1000, actual: 1200, threshold: 0.2), isFalse);
      expect(isOverspent(budget: 1000, actual: 1201, threshold: 0.2), isTrue);
    });
    test('沒預算不算超支', () {
      expect(isOverspent(budget: 0, actual: 9999, threshold: 0.2), isFalse);
    });
  });

  group('月結算', () {
    const rates = PtRates();

    test('兩層都省到：雙重獎勵', () {
      final r = settleMonth(
        groupBudgets: {CategoryGroup.food: 5000, CategoryGroup.entertainment: 2000},
        totalBudget: 10000,
        actualByGroup: {CategoryGroup.food: 4000, CategoryGroup.entertainment: 1500},
        threshold: 0.2,
        rates: rates,
      );
      // 類別：省 1000 → 100 PT、省 500 → 50 PT；總額：省 4500 → 450 PT
      expect(r.categories.map((c) => c.ptDeci), [1000, 500]);
      expect(r.totalPtDeci, 4500);
      expect(r.grossPtDeci, 6000);
      expect(r.isDoubleReward, isTrue);
      expect(r.noPtPenalty, isFalse);
    });

    test('超過半數類別超支 → 當月無 PT', () {
      final r = settleMonth(
        groupBudgets: {
          CategoryGroup.food: 1000,
          CategoryGroup.living: 1000,
          CategoryGroup.learning: 1000,
        },
        totalBudget: 10000,
        actualByGroup: {
          CategoryGroup.food: 2000,
          CategoryGroup.living: 2000,
          CategoryGroup.learning: 0,
        },
        threshold: 0.2,
        rates: rates,
      );
      expect(r.noPtPenalty, isTrue);
      expect(r.grossPtDeci, 0);
    });

    test('剛好一半超支 → 不算「超過半數」', () {
      final r = settleMonth(
        groupBudgets: {CategoryGroup.food: 1000, CategoryGroup.living: 1000},
        totalBudget: null,
        actualByGroup: {CategoryGroup.food: 2000},
        threshold: 0.2,
        rates: rates,
      );
      expect(r.noPtPenalty, isFalse);
      expect(r.grossPtDeci, 1000); // living 省 1000 → 100 PT
    });

    test('只有總額預算', () {
      final r = settleMonth(
        groupBudgets: const {},
        totalBudget: 8000,
        actualByGroup: {CategoryGroup.food: 3000, CategoryGroup.transport: 1000},
        threshold: 0.2,
        rates: rates,
      );
      expect(r.totalPtDeci, 4000);
      expect(r.categories, isEmpty);
    });

    test('沒有支出的類別也算省下全部', () {
      final r = settleMonth(
        groupBudgets: {CategoryGroup.health: 500},
        totalBudget: null,
        actualByGroup: const {},
        threshold: 0.2,
        rates: rates,
      );
      expect(r.categories.single.ptDeci, 500);
    });
  });

  group('PT 格式', () {
    test('formatPt', () {
      expect(formatPt(125), '12.5');
      expect(formatPt(0), '0.0');
      expect(formatPt(-30), '-3.0');
    });
    test('parsePt', () {
      expect(parsePt('12.5'), 125);
      expect(parsePt('500'), 5000);
      expect(parsePt('0.1'), 1);
      expect(parsePt('1.29'), 12);
      expect(parsePt('-1'), isNull);
      expect(parsePt('abc'), isNull);
      expect(parsePt(''), isNull);
    });
  });
}
