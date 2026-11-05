import 'package:sqflite_common/sqlite_api.dart';

import '../domain/date_utils.dart';
import '../domain/items.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'inventory_service.dart' show addItemToInventory;
import 'wallet_service.dart';

class TaskStatus {
  const TaskStatus({
    required this.def,
    required this.completed,
    required this.claimed,
    required this.period,
    this.hint,
  });

  final TaskDef def;
  final bool completed;
  final bool claimed;

  /// 這個任務目前的週期 key（領取時要帶回來）。
  final String period;

  /// 額外說明，例如「3 / 7 天」。
  final String? hint;

  bool get claimable => completed && !claimed;
}

class TaskService {
  TaskService(this.ctx, this.wallet);
  final ServiceContext ctx;
  final WalletService wallet;

  String periodFor(TaskDef def) => switch (def.kind) {
        TaskKind.newbie => '',
        TaskKind.daily => dateKey(ctx.now()),
        TaskKind.fixed => dateKey(ctx.now()),
      };

  /// 標記完成（重複呼叫無害）。回傳是否為「這次才完成」。
  Future<bool> complete(DatabaseExecutor ex, String taskId) async {
    final def = taskById(taskId);
    if (def.kind == TaskKind.fixed && !await _fixedTaskAvailable(ex, def)) {
      return false;
    }
    final id = await ex.insert(
      'task_progress',
      {'task_id': taskId, 'period': periodFor(def), 'completed_at': ctx.nowMs()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  /// 固定任務：距離上一次完成至少 N 天才能再完成。
  Future<bool> _fixedTaskAvailable(DatabaseExecutor ex, TaskDef def) async {
    final rows = await ex.query('task_progress',
        where: 'task_id = ?',
        whereArgs: [def.id],
        orderBy: 'period DESC',
        limit: 1);
    if (rows.isEmpty) return true;
    final last = parseDateKey(rows.first['period'] as String);
    return daysBetween(last, ctx.now()) >= assetUpdateIntervalDays;
  }

  /// 領取獎勵。
  Future<TaskDef> claim(String taskId, String period) async {
    final def = taskById(taskId);
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('task_progress',
          where: 'task_id = ? AND period = ?', whereArgs: [taskId, period]);
      if (rows.isEmpty) throw const UserError('任務尚未完成');
      if (rows.first['claimed_at'] != null) throw const UserError('已經領過了');
      await txn.update('task_progress', {'claimed_at': ctx.nowMs()},
          where: 'task_id = ? AND period = ?', whereArgs: [taskId, period]);
      await wallet.addCoins(txn, CoinSource.task, def.rewardCoins,
          note: def.name);
      if (def.rewardItemId != null) {
        await addItemToInventory(txn, ctx, def.rewardItemId!);
      }
    });
    return def;
  }

  /// 完成並立即領取（簽到用）。已領過則回傳 false。
  Future<bool> completeAndClaim(String taskId) async {
    final def = taskById(taskId);
    final period = periodFor(def);
    await ctx.db.transaction((txn) => complete(txn, taskId));
    final rows = await ctx.db.query('task_progress',
        where: 'task_id = ? AND period = ?', whereArgs: [taskId, period]);
    if (rows.isEmpty || rows.first['claimed_at'] != null) return false;
    await claim(taskId, period);
    return true;
  }

  Future<int> recordedDayCount([DatabaseExecutor? ex]) async {
    final e = ex ?? ctx.db;
    final txnDays = await e.rawQuery(
        "SELECT DISTINCT date(occurred_at / 1000, 'unixepoch', 'localtime') AS d FROM transactions");
    final noSpend = await e.query('no_spend_days', columns: ['date']);
    final days = {
      for (final r in txnDays) r['d'] as String,
      for (final r in noSpend) r['date'] as String,
    };
    return days.length;
  }

  /// 有記帳的事件發生後呼叫：更新相關任務。
  Future<void> onRecorded(DatabaseExecutor ex) async {
    await complete(ex, TaskIds.dailyRecord);
    if (await recordedDayCount(ex) >= 7) {
      await complete(ex, TaskIds.record7Days);
    }
  }

  Future<List<TaskStatus>> statuses() async {
    final out = <TaskStatus>[];
    final days = await recordedDayCount();
    for (final def in taskCatalog) {
      final period = periodFor(def);
      final rows = await ctx.db.query('task_progress',
          where: 'task_id = ? AND period = ?', whereArgs: [def.id, period]);
      String? hint;
      if (def.id == TaskIds.record7Days && rows.isEmpty) {
        hint = '${days.clamp(0, 7)} / 7 天';
      }
      if (def.kind == TaskKind.fixed && rows.isEmpty) {
        final available = await _fixedTaskAvailable(ctx.db, def);
        hint = available ? '今天更新任一資產帳戶即可完成' : '已完成，過幾天再來';
      }
      out.add(TaskStatus(
        def: def,
        completed: rows.isNotEmpty,
        claimed: rows.isNotEmpty && rows.first['claimed_at'] != null,
        period: period,
        hint: hint,
      ));
    }
    return out;
  }

  String rewardText(TaskDef def) {
    final parts = <String>['🪙 ${def.rewardCoins}'];
    if (def.rewardItemId != null) {
      final item = itemById(def.rewardItemId!);
      if (item != null) parts.add('${item.emoji} ${item.name}');
    }
    return parts.join('  ');
  }
}
