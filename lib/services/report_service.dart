import '../domain/date_utils.dart';
import '../domain/enums.dart';
import 'context.dart';

class MonthTotals {
  const MonthTotals(this.month, this.expense, this.income);
  final String month;
  final int expense;
  final int income;
}

class CategoryAmount {
  const CategoryAmount(this.category, this.amount, this.count);
  final Category category;
  final int amount;
  final int count;
}

class PaymentAmount {
  const PaymentAmount(this.name, this.isCreditCard, this.amount);

  /// null 代表沒指定支付工具。
  final String? name;
  final bool isCreditCard;
  final int amount;
}

class MonthReport {
  const MonthReport({
    required this.month,
    required this.expense,
    required this.income,
    required this.saved,
    required this.prevExpense,
    required this.byGroup,
    required this.topCategories,
    required this.byPayment,
    required this.trend,
    required this.daysElapsed,
    required this.recordedDays,
    required this.noSpendDays,
    required this.biggest,
  });

  final String month;
  final int expense;
  final int income;
  final int saved;
  final int prevExpense;
  final Map<CategoryGroup, int> byGroup;
  final List<CategoryAmount> topCategories;
  final List<PaymentAmount> byPayment;

  /// 近 6 個月（舊 → 新，含本月）。
  final List<MonthTotals> trend;

  /// 本月已過天數（過去月份為整月天數）。
  final int daysElapsed;
  final int recordedDays;
  final int noSpendDays;

  /// 本月最大一筆支出 (類別, 金額, 備註)。
  final (Category, int, String?)? biggest;

  int get dailyAverage => daysElapsed == 0 ? 0 : (expense / daysElapsed).round();

  /// 與上月相比的變化比例；上月為 0 時為 null。
  double? get changeVsPrev => prevExpense == 0 ? null : (expense - prevExpense) / prevExpense;
}

class ReportService {
  ReportService(this.ctx);
  final ServiceContext ctx;

  (int, int) _range(String month) {
    final s = parseMonthKey(month);
    return (s.millisecondsSinceEpoch, startOfNextMonth(s).millisecondsSinceEpoch);
  }

  Future<int> _sum(String type, String month) {
    final (a, b) = _range(month);
    return sumInt(ctx.db,
        'SELECT SUM(amount) FROM transactions WHERE type = ? AND occurred_at >= ? AND occurred_at < ?',
        [type, a, b]);
  }

  Future<MonthReport> monthReport(String month) async {
    final (a, b) = _range(month);
    final args = [a, b];

    final catRows = await ctx.db.rawQuery(
      "SELECT category, SUM(amount) AS s, COUNT(*) AS n FROM transactions WHERE type = 'expense' "
      'AND occurred_at >= ? AND occurred_at < ? GROUP BY category ORDER BY s DESC',
      args,
    );
    final cats = <CategoryAmount>[];
    final byGroup = <CategoryGroup, int>{};
    for (final r in catRows) {
      final c = Category.tryParse(r['category'] as String) ?? Category.misc;
      final amt = (r['s'] as num).toInt();
      cats.add(CategoryAmount(c, amt, r['n'] as int));
      byGroup[c.group] = (byGroup[c.group] ?? 0) + amt;
    }

    final payRows = await ctx.db.rawQuery(
      "SELECT p.name AS name, p.type AS ptype, SUM(t.amount) AS s FROM transactions t "
      'LEFT JOIN payment_methods p ON p.id = t.payment_method_id '
      "WHERE t.type = 'expense' AND t.occurred_at >= ? AND t.occurred_at < ? "
      'GROUP BY t.payment_method_id ORDER BY s DESC',
      args,
    );

    final trend = <MonthTotals>[];
    var m = month;
    for (var i = 0; i < 6; i++) {
      trend.insert(0, MonthTotals(m, await _sum('expense', m), await _sum('income', m)));
      m = previousMonthKey(m);
    }

    final start = parseMonthKey(month);
    final now = ctx.now();
    final isCurrent = monthKey(now) == month;
    final daysElapsed = isCurrent ? now.day : daysInMonth(start.year, start.month);

    final dayRows = await ctx.db.rawQuery(
        "SELECT DISTINCT date(occurred_at / 1000, 'unixepoch', 'localtime') AS d "
        'FROM transactions WHERE occurred_at >= ? AND occurred_at < ?',
        args);
    final noSpendRows =
        await ctx.db.query('no_spend_days', where: 'date LIKE ?', whereArgs: ['$month-%']);
    final recorded = {
      for (final r in dayRows) r['d'] as String,
      for (final r in noSpendRows) r['date'] as String,
    };

    final big = await ctx.db.query('transactions',
        where: "type = 'expense' AND occurred_at >= ? AND occurred_at < ?",
        whereArgs: args,
        orderBy: 'amount DESC',
        limit: 1);

    return MonthReport(
      month: month,
      expense: await _sum('expense', month),
      income: await _sum('income', month),
      saved: await sumInt(ctx.db,
          'SELECT SUM(saved_amount) FROM transactions WHERE occurred_at >= ? AND occurred_at < ?', args),
      prevExpense: await _sum('expense', previousMonthKey(month)),
      byGroup: byGroup,
      topCategories: cats.take(5).toList(),
      byPayment: [
        for (final r in payRows)
          PaymentAmount(r['name'] as String?, r['ptype'] == PaymentType.creditCard.name,
              (r['s'] as num).toInt()),
      ],
      trend: trend,
      daysElapsed: daysElapsed,
      recordedDays: recorded.length,
      noSpendDays: noSpendRows.length,
      biggest: big.isEmpty
          ? null
          : (
              Category.tryParse(big.first['category'] as String) ?? Category.misc,
              big.first['amount'] as int,
              big.first['note'] as String?,
            ),
    );
  }

  /// 資產總額歷史：每天取各帳戶最後一次快照加總。回傳 (日期, 總額)，舊 → 新。
  /// （刪除帳戶時 asset_log 會一起刪掉，所以只會算到現存帳戶。）
  Future<List<(DateTime, int)>> netWorthHistory({int days = 90}) async {
    final since = startOfDay(ctx.now()).subtract(Duration(days: days));
    final rows = await ctx.db.query('asset_log', orderBy: 'recorded_at, id');
    final latest = <String, int>{};
    final byDay = <String, int>{};
    for (final r in rows) {
      latest[r['account_id'] as String] = r['balance_snapshot'] as int;
      final t = DateTime.fromMillisecondsSinceEpoch(r['recorded_at'] as int);
      byDay[dateKey(t)] = latest.values.fold(0, (a, b) => a + b);
    }
    return [
      for (final e in byDay.entries)
        if (!parseDateKey(e.key).isBefore(since)) (parseDateKey(e.key), e.value),
    ];
  }
}
