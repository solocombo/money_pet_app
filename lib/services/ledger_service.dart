import 'package:sqflite_common/sqlite_api.dart';

import '../data/app_settings.dart';
import '../data/models.dart';
import '../domain/date_utils.dart';
import '../domain/enums.dart';
import '../domain/items.dart';
import '../domain/pet_rules.dart';
import '../domain/pt_rules.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'inventory_service.dart';
import 'pet_service.dart';
import 'settings_service.dart';
import 'task_service.dart';
import 'wallet_service.dart';

/// 總額預算在 budgets.grp 欄位的值。
const String totalBudgetKey = 'total';

/// 記一筆帳之後發生的所有事，給 UI 顯示用。
class RecordOutcome {
  const RecordOutcome({
    required this.txn,
    this.droppedItem,
    this.dropLimitReached = false,
    this.ptAwardedDeci = 0,
    this.ptRequestedDeci = 0,
    this.noBudget = false,
    this.pastMonth = false,
    this.sanTriggers = const [],
    this.sanCheckFailed = false,
    this.becameInsane = false,
    this.newCondition,
    this.cancelledNoSpend = false,
  });

  final Txn txn;
  final ItemDef? droppedItem;
  final bool dropLimitReached;
  final int ptAwardedDeci;

  /// 套用上限前的 PT；與 [ptAwardedDeci] 不同代表被上限擋掉了。
  final int ptRequestedDeci;

  /// 該月沒有設定任何預算 → 不給 PT，只給道具。
  final bool noBudget;

  /// 記的是過去月份的帳 → 不給 PT（避免補記舊帳刷 PT）。
  final bool pastMonth;
  final List<SanTrigger> sanTriggers;
  final bool sanCheckFailed;
  final bool becameInsane;
  final ConditionType? newCondition;

  /// 今天原本按了本日無支出，記了支出後被取消。
  final bool cancelledNoSpend;

  bool get ptCapped => ptRequestedDeci > ptAwardedDeci;
}

class BudgetSet {
  const BudgetSet({this.total, this.groups = const {}});
  final int? total;
  final Map<CategoryGroup, int> groups;
  bool get isEmpty => total == null && groups.isEmpty;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.expense,
    required this.income,
    required this.saved,
    required this.byGroup,
    required this.budgets,
    required this.ptEarnedDeci,
    required this.ptCapDeci,
  });

  final String month;
  final int expense;
  final int income;
  final int saved;
  final Map<CategoryGroup, int> byGroup;
  final BudgetSet budgets;

  /// 本月已計入上限的 PT。
  final int ptEarnedDeci;
  final int ptCapDeci;
}

class LedgerService {
  LedgerService(this.ctx, this.settings, this.wallet, this.pets, this.tasks);
  final ServiceContext ctx;
  final SettingsService settings;
  final WalletService wallet;
  final PetService pets;
  final TaskService tasks;

  // ---- 記帳 ----

  Future<RecordOutcome> addExpense({
    required Category category,
    required int amount,
    int savedAmount = 0,
    String? paymentMethodId,
    String? note,
    DateTime? occurredAt,
  }) =>
      _add(
        type: TransactionType.expense,
        categoryName: category.name,
        category: category,
        amount: amount,
        savedAmount: savedAmount,
        paymentMethodId: paymentMethodId,
        note: note,
        occurredAt: occurredAt,
      );

  Future<RecordOutcome> addIncome({
    required IncomeCategory category,
    required int amount,
    String? paymentMethodId,
    String? note,
    DateTime? occurredAt,
  }) =>
      _add(
        type: TransactionType.income,
        categoryName: category.name,
        amount: amount,
        savedAmount: 0,
        paymentMethodId: paymentMethodId,
        note: note,
        occurredAt: occurredAt,
      );

  Future<RecordOutcome> _add({
    required TransactionType type,
    required String categoryName,
    Category? category,
    required int amount,
    required int savedAmount,
    String? paymentMethodId,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (amount <= 0) throw const UserError('金額要大於 0');
    final savedErr = validateSavedAmount(amount: amount, saved: savedAmount);
    if (savedErr != null) throw UserError(savedErr);
    final now = ctx.now();
    final at = occurredAt ?? now;
    if (at.isAfter(now.add(const Duration(minutes: 5)))) {
      throw const UserError('不能記未來的帳');
    }

    // 先把寵物推進到今天，避免結算順序錯亂。
    await pets.tick();
    final s = await settings.load();
    final id = ctx.newId();
    final txMonth = monthKey(at);
    final isExpense = type == TransactionType.expense;

    late RecordOutcome outcome;
    await ctx.db.transaction((txn) async {
      await txn.insert('transactions', {
        'id': id,
        'type': type.name,
        'category': categoryName,
        'amount': amount,
        'saved_amount': savedAmount,
        'payment_method_id': paymentMethodId,
        'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
        'occurred_at': at.millisecondsSinceEpoch,
        'created_at': now.millisecondsSinceEpoch,
      });

      // 記了支出 → 那天就不算「無支出」。
      var cancelledNoSpend = false;
      if (isExpense) cancelledNoSpend = await _cancelNoSpend(txn, dateKey(at));

      // ---- PT ----
      final budgets = await budgetsFor(txMonth, txn);
      final pastMonth = txMonth != monthKey(now);
      var requested = 0;
      var awarded = 0;
      if (!budgets.isEmpty && !pastMonth) {
        requested = isExpense
            ? ptFromAmount(savedAmount, s.ptRates.savedAmount)
            : ptFromAmount(amount, s.ptRates.income);
        awarded = await wallet.addPt(
          txn,
          isExpense ? PtSource.saved : PtSource.income,
          requested,
          period: txMonth,
          rates: s.ptRates,
          refId: id,
          note: isExpense ? '省下 $savedAmount 元' : '收入記帳',
        );
      }

      // ---- 道具掉落 + 寵物 ----
      ItemDef? dropped;
      var limitReached = false;
      final pet = await pets.activePet(txn);
      var stats = pet?.stats;
      if (await _consumeDropQuota(txn, s)) {
        dropped = rollItemDrop(ctx.random);
        await addItemToInventory(txn, ctx, dropped.id);
        if (stats != null && category != null) {
          stats = applyRecordBonus(stats, category);
        }
      } else {
        limitReached = true;
      }

      // ---- San check ----
      var triggers = const <SanTrigger>[];
      var failed = false;
      var becameInsane = false;
      if (isExpense && stats != null && !s.disableSanCheck) {
        triggers = sanTriggers(await _sanInput(txn, s, category!, amount, at, budgets));
        final wasInsane = stats.isInsane;
        final r = runSanCheck(stats, triggers, ctx.random);
        stats = r.stats;
        failed = r.failed;
        becameInsane = !wasInsane && stats.isInsane;
      }
      if (pet != null && stats != null) await pets.saveStats(txn, pet.id, stats);

      // ---- 超支生病 ----
      ConditionType? newCondition;
      if (isExpense && !pastMonth) {
        final group = category!.group;
        final groupBudget = budgets.groups[group];
        if (groupBudget != null) {
          final spent = await _groupSpent(txn, group, txMonth);
          if (isOverspent(
              budget: groupBudget, actual: spent, threshold: s.overspendThreshold)) {
            newCondition = await pets.triggerOverspendCondition(txn, group, txMonth);
          }
        }
      }

      await txn.update(
        'transactions',
        {'pt_awarded': awarded, 'dropped_item_id': dropped?.id},
        where: 'id = ?',
        whereArgs: [id],
      );

      await tasks.complete(txn, TaskIds.firstTransaction);
      await tasks.onRecorded(txn);

      final row = (await txn.query('transactions', where: 'id = ?', whereArgs: [id])).first;
      outcome = RecordOutcome(
        txn: Txn.fromRow(row),
        droppedItem: dropped,
        dropLimitReached: limitReached,
        ptAwardedDeci: awarded,
        ptRequestedDeci: requested,
        noBudget: budgets.isEmpty,
        pastMonth: pastMonth,
        sanTriggers: triggers,
        sanCheckFailed: failed,
        becameInsane: becameInsane,
        newCondition: newCondition,
        cancelledNoSpend: cancelledNoSpend,
      );
    });
    return outcome;
  }

  /// 每日掉落次數用「計數器」而不是數交易筆數，
  /// 這樣「新增 → 用掉道具 → 刪除」重複操作也刷不到更多道具。
  Future<bool> _consumeDropQuota(DatabaseExecutor ex, AppSettings s) async {
    final key = 'drop_count:${dateKey(ctx.now())}';
    final used = int.tryParse(await settings.getRaw(key, ex) ?? '') ?? 0;
    if (used >= s.dailyDropLimit) return false;
    await settings.setRaw(key, '${used + 1}', ex);
    return true;
  }

  Future<SanCheckInput> _sanInput(DatabaseExecutor ex, AppSettings s,
      Category category, int amount, DateTime at, BudgetSet budgets) async {
    final dayStart = startOfDay(at);
    final dayEnd = DateTime(at.year, at.month, at.day + 1);
    final sameCat = await sumInt(
      ex,
      "SELECT COUNT(*) FROM transactions WHERE type = 'expense' AND category = ? "
      'AND occurred_at >= ? AND occurred_at < ?',
      [category.name, dayStart.millisecondsSinceEpoch, dayEnd.millisecondsSinceEpoch],
    );
    return SanCheckInput(
      amount: amount,
      occurredAt: at,
      sameCategoryCountToday: sameCat,
      impulseThreshold: s.impulseThreshold,
      repeatThreshold: s.repeatCategoryThreshold,
      monthBudget: budgets.total,
      monthSpentIncludingThis: await _monthExpense(ex, monthKey(at)),
    );
  }

  Future<bool> _cancelNoSpend(DatabaseExecutor ex, String date) async {
    final n = await ex.delete('no_spend_days', where: 'date = ?', whereArgs: [date]);
    if (n == 0) return false;
    await wallet.addCoins(ex, CoinSource.reversal, -noSpendCoinReward,
        note: '取消本日無支出');
    return true;
  }

  /// 編輯交易。PT 會依新內容重算（先退回舊的、再發新的，月上限也跟著正確）。
  /// **不會**重新掉道具、也不會觸發 San check（避免靠編輯刷）。
  /// 回傳新的 PT 與是否觸發生病。
  Future<RecordOutcome> updateTransaction(
    String id, {
    required String categoryName,
    required int amount,
    int savedAmount = 0,
    String? paymentMethodId,
    String? note,
    required DateTime occurredAt,
  }) async {
    if (amount <= 0) throw const UserError('金額要大於 0');
    final now = ctx.now();
    if (occurredAt.isAfter(now.add(const Duration(minutes: 5)))) {
      throw const UserError('不能記未來的帳');
    }
    final s = await settings.load();
    late RecordOutcome outcome;
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const UserError('找不到這筆紀錄');
      final old = Txn.fromRow(rows.first);
      final isExpense = old.isExpense;
      final category = isExpense ? Category.tryParse(categoryName) : null;
      if (isExpense && category == null) throw const UserError('類別不正確');
      final saved = isExpense ? savedAmount : 0;
      final err = validateSavedAmount(amount: amount, saved: saved);
      if (err != null) throw UserError(err);

      if (old.ptAwardedDeci > 0) {
        await txn.insert('pt_log', {
          'source': PtSource.reversal.name,
          'amount': -old.ptAwardedDeci,
          'period': monthKey(old.occurredAt),
          'note': '編輯交易',
          'ref_id': id,
          'created_at': ctx.nowMs(),
        });
      }
      await txn.update(
        'transactions',
        {
          'category': categoryName,
          'amount': amount,
          'saved_amount': saved,
          'payment_method_id': paymentMethodId,
          'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
          'occurred_at': occurredAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      var cancelledNoSpend = false;
      if (isExpense) cancelledNoSpend = await _cancelNoSpend(txn, dateKey(occurredAt));

      final month = monthKey(occurredAt);
      final budgets = await budgetsFor(month, txn);
      final pastMonth = month != monthKey(now);
      var requested = 0;
      var awarded = 0;
      if (!budgets.isEmpty && !pastMonth) {
        requested = isExpense
            ? ptFromAmount(saved, s.ptRates.savedAmount)
            : ptFromAmount(amount, s.ptRates.income);
        awarded = await wallet.addPt(
          txn,
          isExpense ? PtSource.saved : PtSource.income,
          requested,
          period: month,
          rates: s.ptRates,
          refId: id,
          note: '編輯交易',
        );
      }
      await txn.update('transactions', {'pt_awarded': awarded},
          where: 'id = ?', whereArgs: [id]);

      ConditionType? newCondition;
      if (isExpense && !pastMonth) {
        final group = category!.group;
        final groupBudget = budgets.groups[group];
        if (groupBudget != null &&
            isOverspent(
                budget: groupBudget,
                actual: await _groupSpent(txn, group, month),
                threshold: s.overspendThreshold)) {
          newCondition = await pets.triggerOverspendCondition(txn, group, month);
        }
      }

      final row = (await txn.query('transactions', where: 'id = ?', whereArgs: [id])).first;
      outcome = RecordOutcome(
        txn: Txn.fromRow(row),
        ptAwardedDeci: awarded,
        ptRequestedDeci: requested,
        noBudget: budgets.isEmpty,
        pastMonth: pastMonth,
        newCondition: newCondition,
        cancelledNoSpend: cancelledNoSpend,
      );
    });
    return outcome;
  }

  /// 刪除交易：退回這筆發的 PT，背包裡還有的話也收回掉落的道具。
  Future<void> deleteTransaction(String id) async {
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final t = Txn.fromRow(rows.first);
      if (t.ptAwardedDeci > 0) {
        await txn.insert('pt_log', {
          'source': PtSource.reversal.name,
          'amount': -t.ptAwardedDeci,
          'period': monthKey(t.occurredAt),
          'note': '刪除交易',
          'ref_id': t.id,
          'created_at': ctx.nowMs(),
        });
      }
      if (t.droppedItemId != null) {
        await removeItemFromInventory(txn, t.droppedItemId!);
      }
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Txn>> transactionsInMonth(String month) async {
    final start = parseMonthKey(month);
    final end = startOfNextMonth(start);
    final rows = await ctx.db.query('transactions',
        where: 'occurred_at >= ? AND occurred_at < ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        orderBy: 'occurred_at DESC, created_at DESC');
    return rows.map(Txn.fromRow).toList();
  }

  Future<List<Txn>> recentTransactions({int limit = 5}) async {
    final rows = await ctx.db.query('transactions',
        orderBy: 'occurred_at DESC, created_at DESC', limit: limit);
    return rows.map(Txn.fromRow).toList();
  }

  // ---- 本日無支出 ----

  Future<bool> isNoSpendToday() async => (await ctx.db.query('no_spend_days',
          where: 'date = ?', whereArgs: [dateKey(ctx.now())]))
      .isNotEmpty;

  Future<bool> hasExpenseToday([DatabaseExecutor? ex]) async {
    final now = ctx.now();
    final start = startOfDay(now);
    final end = DateTime(now.year, now.month, now.day + 1);
    return await sumInt(
          ex ?? ctx.db,
          "SELECT COUNT(*) FROM transactions WHERE type = 'expense' "
          'AND occurred_at >= ? AND occurred_at < ?',
          [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        ) >
        0;
  }

  /// 本日無支出打卡：完成每日記帳任務、飽食值當天只降一半、給少量金幣。
  /// 不計入省錢 PT。
  Future<void> checkInNoSpend() async {
    await ctx.db.transaction((txn) async {
      if (await hasExpenseToday(txn)) {
        throw const UserError('今天已經有支出紀錄了');
      }
      final id = await txn.insert(
        'no_spend_days',
        {'date': dateKey(ctx.now()), 'created_at': ctx.nowMs()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (id == 0) throw const UserError('今天已經打過卡了');
      await wallet.addCoins(txn, CoinSource.noSpend, noSpendCoinReward,
          note: '本日無支出');
      await tasks.onRecorded(txn);
    });
  }

  // ---- 預算 ----

  Future<BudgetSet> budgetsFor(String month, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db)
        .query('budgets', where: 'month = ?', whereArgs: [month]);
    int? total;
    final groups = <CategoryGroup, int>{};
    for (final r in rows) {
      final g = r['grp'] as String;
      final amount = r['amount'] as int;
      if (g == totalBudgetKey) {
        total = amount;
      } else {
        for (final cg in CategoryGroup.values) {
          if (cg.name == g) groups[cg] = amount;
        }
      }
    }
    return BudgetSet(total: total, groups: groups);
  }

  /// 設定某月預算。amount 為 null 或 <= 0 代表移除。
  Future<void> setBudget(String month, CategoryGroup? group, int? amount) async {
    final key = group?.name ?? totalBudgetKey;
    if (amount == null || amount <= 0) {
      await ctx.db.delete('budgets',
          where: 'month = ? AND grp = ?', whereArgs: [month, key]);
      return;
    }
    await ctx.db.insert('budgets', {'month': month, 'grp': key, 'amount': amount},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> _monthExpense(DatabaseExecutor ex, String month) {
    final start = parseMonthKey(month);
    final end = startOfNextMonth(start);
    return sumInt(
      ex,
      "SELECT SUM(amount) FROM transactions WHERE type = 'expense' "
      'AND occurred_at >= ? AND occurred_at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
  }

  Future<int> _groupSpent(DatabaseExecutor ex, CategoryGroup group, String month) async =>
      (await _spentByGroup(ex, month))[group] ?? 0;

  Future<Map<CategoryGroup, int>> _spentByGroup(DatabaseExecutor ex, String month) async {
    final start = parseMonthKey(month);
    final end = startOfNextMonth(start);
    final rows = await ex.rawQuery(
      "SELECT category, SUM(amount) AS s FROM transactions WHERE type = 'expense' "
      'AND occurred_at >= ? AND occurred_at < ? GROUP BY category',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    final out = <CategoryGroup, int>{};
    for (final r in rows) {
      final c = Category.tryParse(r['category'] as String) ?? Category.misc;
      out[c.group] = (out[c.group] ?? 0) + (r['s'] as num).toInt();
    }
    return out;
  }

  Future<MonthSummary> summary(String month) async {
    final start = parseMonthKey(month);
    final end = startOfNextMonth(start);
    final args = [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    final s = await settings.load();
    return MonthSummary(
      month: month,
      expense: await _monthExpense(ctx.db, month),
      income: await sumInt(
          ctx.db,
          "SELECT SUM(amount) FROM transactions WHERE type = 'income' "
          'AND occurred_at >= ? AND occurred_at < ?',
          args),
      saved: await sumInt(
          ctx.db,
          'SELECT SUM(saved_amount) FROM transactions WHERE occurred_at >= ? AND occurred_at < ?',
          args),
      byGroup: await _spentByGroup(ctx.db, month),
      budgets: await budgetsFor(month),
      ptEarnedDeci: await wallet.cappedEarnedInPeriod(month),
      ptCapDeci: s.ptRates.monthlyCapDeci,
    );
  }

  // ---- 月結算 ----

  /// 新的月份還沒設預算時，沿用上個月的預算（不然使用者會默默拿不到 PT）。
  Future<bool> carryOverBudgets() async {
    final month = monthKey(ctx.now());
    if (!(await budgetsFor(month)).isEmpty) return false;
    final prev = await ctx.db.query('budgets',
        where: 'month = ?', whereArgs: [previousMonthKey(month)]);
    if (prev.isEmpty) return false;
    final batch = ctx.db.batch();
    for (final r in prev) {
      batch.insert('budgets', {'month': month, 'grp': r['grp'], 'amount': r['amount']},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    return true;
  }

  /// 結算所有「已經結束、有設預算、還沒結算」的月份。回傳結算結果。
  Future<List<(String, MonthSettlement, int)>> settlePendingMonths() async {
    final current = monthKey(ctx.now());
    final rows = await ctx.db.rawQuery(
      'SELECT DISTINCT month FROM budgets WHERE month < ? '
      'AND month NOT IN (SELECT month FROM month_settlements) ORDER BY month',
      [current],
    );
    final s = await settings.load();
    final out = <(String, MonthSettlement, int)>[];
    for (final r in rows) {
      final month = r['month'] as String;
      await ctx.db.transaction((txn) async {
        final budgets = await budgetsFor(month, txn);
        final result = settleMonth(
          groupBudgets: budgets.groups,
          totalBudget: budgets.total,
          actualByGroup: await _spentByGroup(txn, month),
          threshold: s.overspendThreshold,
          rates: s.ptRates,
        );
        final awarded = await wallet.addPt(
          txn,
          PtSource.settlement,
          result.grossPtDeci,
          period: month,
          rates: s.ptRates,
          note: '$month 月結算',
        );
        for (final c in result.categories) {
          await txn.insert('budget_results', {
            'month': month,
            'grp': c.group.name,
            'budget_amount': c.budget,
            'actual_amount': c.actual,
            'pt_earned': c.ptDeci,
            'is_overspent': c.overspent ? 1 : 0,
            'created_at': ctx.nowMs(),
          });
        }
        if (result.totalBudget != null) {
          await txn.insert('budget_results', {
            'month': month,
            'grp': totalBudgetKey,
            'budget_amount': result.totalBudget,
            'actual_amount': result.totalActual,
            'pt_earned': result.totalPtDeci,
            'is_overspent': isOverspent(
                    budget: result.totalBudget!,
                    actual: result.totalActual,
                    threshold: s.overspendThreshold)
                ? 1
                : 0,
            'created_at': ctx.nowMs(),
          });
        }
        await txn.insert('month_settlements', {
          'month': month,
          'no_pt_penalty': result.noPtPenalty ? 1 : 0,
          'gross_pt': result.grossPtDeci,
          'awarded_pt': awarded,
          'settled_at': ctx.nowMs(),
        });
        out.add((month, result, awarded));
      });
    }
    return out;
  }
}
