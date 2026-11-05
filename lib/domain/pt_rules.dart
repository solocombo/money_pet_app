import 'enums.dart';

/// PT 計算規則（純函式，方便單元測試）。
///
/// **單位**：程式內部的 PT 一律用「deci-PT」整數（1 = 0.1 PT），
/// 這樣「保留小數後一位」就不會有浮點誤差。顯示時再除以 10。
/// 1 deci-PT 剛好等於 1 金幣（1 PT = 10 金幣）。
class PtRates {
  const PtRates({
    this.categorySaving = 0.1,
    this.totalSaving = 0.1,
    this.income = 0.01,
    this.savedAmount = 0.1,
    this.monthlyCapDeci = 20000,
  });

  /// 類別層省錢：省下金額 × 0.1。
  final double categorySaving;

  /// 總額層省錢：省下金額 × 0.1。
  final double totalSaving;

  /// 收入記帳：收入金額 × 0.01。
  final double income;

  /// 消費省下金額（回饋、折扣）：填入金額 × 0.1。
  final double savedAmount;

  /// 每月自動 PT 上限（deci-PT）。0 代表不設上限。預設 2000 PT。
  ///
  /// 涵蓋收入、省下金額、月結算三種自動來源；
  /// 財務目標是使用者自己定價的承諾，不受此上限影響。
  final int monthlyCapDeci;

  PtRates copyWith({
    double? categorySaving,
    double? totalSaving,
    double? income,
    double? savedAmount,
    int? monthlyCapDeci,
  }) =>
      PtRates(
        categorySaving: categorySaving ?? this.categorySaving,
        totalSaving: totalSaving ?? this.totalSaving,
        income: income ?? this.income,
        savedAmount: savedAmount ?? this.savedAmount,
        monthlyCapDeci: monthlyCapDeci ?? this.monthlyCapDeci,
      );
}

/// 金額 × 比率 → deci-PT，**無條件捨去**到小數後一位。
int ptFromAmount(int amount, double rate) {
  if (amount <= 0 || rate <= 0) return 0;
  // +1e-9 避免 0.1 這類二進位無法精確表示的比率造成 6.9999… 被捨成 6。
  return (amount * rate * 10 + 1e-9).floor();
}

/// 套用每月上限後，實際能入帳的 deci-PT。
int applyMonthlyCap({
  required int requestedDeci,
  required int alreadyEarnedDeci,
  required int capDeci,
}) {
  if (requestedDeci <= 0) return 0;
  if (capDeci <= 0) return requestedDeci;
  final room = capDeci - alreadyEarnedDeci;
  if (room <= 0) return 0;
  return requestedDeci < room ? requestedDeci : room;
}

/// 驗證「本次省下金額」：不能是負數，也不能超過消費金額。
/// 回傳錯誤訊息，合法時回傳 null。
String? validateSavedAmount({required int amount, required int saved}) {
  if (saved < 0) return '省下金額不能是負數';
  if (saved > amount) return '省下金額不能超過消費金額';
  return null;
}

/// 「是否超支」：實際 > 預算 × (1 + 閾值)。
bool isOverspent({
  required int budget,
  required int actual,
  required double threshold,
}) {
  if (budget <= 0) return false;
  return actual > budget * (1 + threshold);
}

class CategorySettlement {
  const CategorySettlement({
    required this.group,
    required this.budget,
    required this.actual,
    required this.ptDeci,
    required this.overspent,
  });

  final CategoryGroup group;
  final int budget;
  final int actual;
  final int ptDeci;
  final bool overspent;

  int get saved => budget > actual ? budget - actual : 0;
}

/// 預算暴擊：總額省下至少這個比例，且沒有任何類別超支 → 結算 PT 加倍。
const double budgetCritSavingRatio = 0.2;

class MonthSettlement {
  const MonthSettlement({
    required this.categories,
    required this.totalBudget,
    required this.totalActual,
    required this.totalPtDeci,
    required this.noPtPenalty,
    this.budgetCrit = false,
  });

  final List<CategorySettlement> categories;
  final int? totalBudget;
  final int totalActual;
  final int totalPtDeci;

  /// 超過半數有預算的類別同時超支 → 當月無法獲得任何結算 PT。
  final bool noPtPenalty;

  /// 預算暴擊（雙倍 PT）。
  final bool budgetCrit;

  /// 套用懲罰與暴擊後、套用上限前的結算 PT。
  int get grossPtDeci {
    if (noPtPenalty) return 0;
    final base = categories.fold<int>(0, (s, c) => s + c.ptDeci) + totalPtDeci;
    return budgetCrit ? base * 2 : base;
  }

  /// 兩層都有省到 → 雙重獎勵（用於 UI 提示）。
  bool get isDoubleReward =>
      !noPtPenalty &&
      totalPtDeci > 0 &&
      categories.any((c) => c.ptDeci > 0);
}

/// 月底結算。
///
/// [groupBudgets]：有設定預算的類別 → 預算金額。
/// [totalBudget]：總額預算，null 代表沒設。
/// [actualByGroup]：該月各類別實際支出。
MonthSettlement settleMonth({
  required Map<CategoryGroup, int> groupBudgets,
  required int? totalBudget,
  required Map<CategoryGroup, int> actualByGroup,
  required double threshold,
  required PtRates rates,
}) {
  final cats = <CategorySettlement>[];
  for (final entry in groupBudgets.entries) {
    if (entry.value <= 0) continue;
    final actual = actualByGroup[entry.key] ?? 0;
    final saved = entry.value - actual;
    cats.add(CategorySettlement(
      group: entry.key,
      budget: entry.value,
      actual: actual,
      ptDeci: saved > 0 ? ptFromAmount(saved, rates.categorySaving) : 0,
      overspent:
          isOverspent(budget: entry.value, actual: actual, threshold: threshold),
    ));
  }

  final totalActual = actualByGroup.values.fold<int>(0, (s, v) => s + v);
  var totalPt = 0;
  if (totalBudget != null && totalBudget > totalActual) {
    totalPt = ptFromAmount(totalBudget - totalActual, rates.totalSaving);
  }

  final overspentCount = cats.where((c) => c.overspent).length;
  final penalty = cats.isNotEmpty && overspentCount * 2 > cats.length;
  final crit = !penalty &&
      overspentCount == 0 &&
      totalBudget != null &&
      totalBudget > 0 &&
      totalBudget - totalActual >= totalBudget * budgetCritSavingRatio;

  return MonthSettlement(
    categories: cats,
    totalBudget: totalBudget,
    totalActual: totalActual,
    totalPtDeci: totalPt,
    noPtPenalty: penalty,
    budgetCrit: crit,
  );
}

/// deci-PT → 顯示字串，例如 125 → "12.5"。
String formatPt(int deci) {
  final sign = deci < 0 ? '-' : '';
  final abs = deci.abs();
  return '$sign${abs ~/ 10}.${abs % 10}';
}

/// 使用者輸入的 PT 字串 → deci-PT。接受 "12"、"12.5"；超過一位小數會捨去。
int? parsePt(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v.isInfinite || v.isNaN) return null;
  return (v * 10 + 1e-9).floor();
}
