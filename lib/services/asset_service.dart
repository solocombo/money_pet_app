import 'package:sqflite_common/sqlite_api.dart';

import '../data/models.dart';
import '../domain/enums.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'task_service.dart';

class AssetService {
  AssetService(this.ctx, this.tasks);
  final ServiceContext ctx;
  final TaskService tasks;

  Future<List<AssetAccount>> accounts() async {
    final rows = await ctx.db.query('asset_accounts', orderBy: 'created_at');
    final stocks = (await ctx.db.query('asset_stocks', orderBy: 'created_at'))
        .map(AssetStock.fromRow)
        .toList();
    return [
      for (final r in rows)
        AssetAccount.fromRow(r).withStocks(
            stocks.where((s) => s.accountId == r['id']).toList()),
    ];
  }

  Future<double> netWorth() async =>
      (await accounts()).fold<double>(0, (s, a) => s + a.total);

  /// 最久沒更新的帳戶時間（用於「三天沒更新」提醒）。沒有帳戶回傳 null。
  Future<DateTime?> oldestUpdate() async {
    final list = await accounts();
    if (list.isEmpty) return null;
    DateTime? oldest;
    for (final a in list) {
      final t = a.lastUpdated;
      if (t == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (oldest == null || t.isBefore(oldest)) oldest = t;
    }
    return oldest;
  }

  Future<void> addAccount(String name, AssetType type, int balance) async {
    if (name.trim().isEmpty) throw const UserError('請輸入帳戶名稱');
    final id = ctx.newId();
    await ctx.db.transaction((txn) async {
      await txn.insert('asset_accounts', {
        'id': id,
        'name': name.trim(),
        'type': type.name,
        'balance': balance,
        'last_updated': ctx.nowMs(),
        'created_at': ctx.nowMs(),
      });
      await _snapshot(txn, id);
      await tasks.complete(txn, TaskIds.assetUpdate);
    });
  }

  Future<void> updateBalance(String accountId, int balance) async {
    await ctx.db.transaction((txn) async {
      await txn.update(
          'asset_accounts', {'balance': balance, 'last_updated': ctx.nowMs()},
          where: 'id = ?', whereArgs: [accountId]);
      await _snapshot(txn, accountId);
      await tasks.complete(txn, TaskIds.assetUpdate);
    });
  }

  Future<void> renameAccount(String accountId, String name) async {
    if (name.trim().isEmpty) return;
    await ctx.db.update('asset_accounts', {'name': name.trim()},
        where: 'id = ?', whereArgs: [accountId]);
  }

  Future<void> deleteAccount(String accountId) =>
      ctx.db.delete('asset_accounts', where: 'id = ?', whereArgs: [accountId]);

  Future<void> upsertStock({
    String? id,
    required String accountId,
    required String name,
    String? code,
    required double quantity,
    required double price,
  }) async {
    if (name.trim().isEmpty) throw const UserError('請輸入股票名稱');
    if (quantity < 0 || price < 0) throw const UserError('數量與股價不能是負數');
    await ctx.db.transaction((txn) async {
      final row = {
        'account_id': accountId,
        'stock_name': name.trim(),
        'stock_code': (code?.trim().isEmpty ?? true) ? null : code!.trim(),
        'quantity': quantity,
        'current_price': price,
        'last_updated': ctx.nowMs(),
      };
      if (id == null) {
        await txn.insert('asset_stocks',
            {...row, 'id': ctx.newId(), 'created_at': ctx.nowMs()});
      } else {
        await txn.update('asset_stocks', row, where: 'id = ?', whereArgs: [id]);
      }
      await txn.update('asset_accounts', {'last_updated': ctx.nowMs()},
          where: 'id = ?', whereArgs: [accountId]);
      await _snapshot(txn, accountId);
      await tasks.complete(txn, TaskIds.assetUpdate);
    });
  }

  Future<void> deleteStock(String id) =>
      ctx.db.delete('asset_stocks', where: 'id = ?', whereArgs: [id]);

  /// 記錄帳戶總額快照（之後畫歷史趨勢圖用）。
  Future<void> _snapshot(DatabaseExecutor ex, String accountId) async {
    final cash = await sumInt(
        ex, 'SELECT balance FROM asset_accounts WHERE id = ?', [accountId]);
    final stockRows = await ex.rawQuery(
        'SELECT SUM(quantity * current_price) AS v FROM asset_stocks WHERE account_id = ?',
        [accountId]);
    final stock = (stockRows.first['v'] as num?)?.toDouble() ?? 0;
    await ex.insert('asset_log', {
      'account_id': accountId,
      'balance_snapshot': (cash + stock).round(),
      'recorded_at': ctx.nowMs(),
    });
  }
}
