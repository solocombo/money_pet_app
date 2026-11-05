import '../data/models.dart';
import '../domain/date_utils.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'settings_service.dart';
import 'task_service.dart';
import 'wallet_service.dart';

/// 獎勵櫃 + 財務目標。
class RewardService {
  RewardService(this.ctx, this.settings, this.wallet, this.tasks);
  final ServiceContext ctx;
  final SettingsService settings;
  final WalletService wallet;
  final TaskService tasks;

  // ---- 獎勵櫃 ----

  Future<List<Reward>> rewards() async {
    final rows = await ctx.db
        .query('rewards', orderBy: 'is_redeemed, pt_cost, created_at');
    return rows.map(Reward.fromRow).toList();
  }

  Future<void> addReward(String name, int ptCostDeci) async {
    if (name.trim().isEmpty) throw const UserError('請輸入獎勵名稱');
    if (ptCostDeci <= 0) throw const UserError('PT 要大於 0');
    await ctx.db.transaction((txn) async {
      await txn.insert('rewards', {
        'id': ctx.newId(),
        'name': name.trim(),
        'pt_cost': ptCostDeci,
        'created_at': ctx.nowMs(),
      });
      await tasks.complete(txn, TaskIds.firstReward);
    });
  }

  Future<void> deleteReward(String id) =>
      ctx.db.delete('rewards', where: 'id = ?', whereArgs: [id]);

  Future<void> redeem(String id) async {
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('rewards', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const UserError('找不到這個獎勵');
      final r = Reward.fromRow(rows.first);
      if (r.isRedeemed) throw const UserError('已經兌換過了');
      if (await wallet.ptBalanceDeci(txn) < r.ptCostDeci) {
        throw const UserError('PT 不足');
      }
      await txn.insert('pt_log', {
        'source': PtSource.redeem.name,
        'amount': -r.ptCostDeci,
        'period': monthKey(ctx.now()),
        'note': '兌換 ${r.name}',
        'ref_id': r.id,
        'created_at': ctx.nowMs(),
      });
      await txn.update('rewards', {'is_redeemed': 1, 'redeemed_at': ctx.nowMs()},
          where: 'id = ?', whereArgs: [id]);
      await tasks.complete(txn, TaskIds.firstRedeem);
    });
  }

  // ---- 財務目標 ----

  Future<List<FinancialGoal>> goals() async {
    final rows =
        await ctx.db.query('financial_goals', orderBy: 'is_completed, deadline');
    return rows.map(FinancialGoal.fromRow).toList();
  }

  Future<void> addGoal({
    required String name,
    String? description,
    required int ptRewardDeci,
    required DateTime deadline,
  }) async {
    if (name.trim().isEmpty) throw const UserError('請輸入目標名稱');
    if (ptRewardDeci <= 0) throw const UserError('PT 獎勵要大於 0');
    if (deadline.isBefore(startOfDay(ctx.now()))) {
      throw const UserError('截止日不能早於今天');
    }
    await ctx.db.transaction((txn) async {
      await txn.insert('financial_goals', {
        'id': ctx.newId(),
        'name': name.trim(),
        'description':
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        'pt_reward': ptRewardDeci,
        'deadline': dateKey(deadline),
        'created_at': ctx.nowMs(),
      });
      await tasks.complete(txn, TaskIds.firstGoal);
    });
  }

  Future<void> deleteGoal(String id) =>
      ctx.db.delete('financial_goals', where: 'id = ?', whereArgs: [id]);

  /// 手動打勾領取 PT。過期的目標不能領。財務目標不受每月 PT 上限限制。
  Future<int> completeGoal(String id) async {
    late int reward;
    await ctx.db.transaction((txn) async {
      final rows =
          await txn.query('financial_goals', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const UserError('找不到這個目標');
      final g = FinancialGoal.fromRow(rows.first);
      if (g.isCompleted) throw const UserError('已經完成了');
      if (startOfDay(ctx.now()).isAfter(parseDateKey(g.deadline))) {
        throw const UserError('已經過了截止日');
      }
      final s = await settings.load(txn);
      reward = await wallet.addPt(txn, PtSource.goal, g.ptRewardDeci,
          period: monthKey(ctx.now()),
          rates: s.ptRates,
          note: '完成目標：${g.name}',
          refId: g.id);
      await txn.update(
          'financial_goals', {'is_completed': 1, 'completed_at': ctx.nowMs()},
          where: 'id = ?', whereArgs: [id]);
    });
    return reward;
  }
}
