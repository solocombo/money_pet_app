import 'package:sqflite_common/sqlite_api.dart';

import '../domain/date_utils.dart';
import '../domain/items.dart';
import 'context.dart';
import 'inventory_service.dart';
import 'settings_service.dart';
import 'wallet_service.dart';

/// 看廣告換金幣：每次 30，每天 5 次。
const int adCoinReward = 30;
const int adCoinDailyLimit = 5;

/// 看廣告重抽道具：每天 2 次，只能重抽今天記帳掉的道具。
const int rerollDailyLimit = 2;

enum AdRewardKind {
  coins('ad_coins', adCoinDailyLimit),
  reroll('ad_reroll', rerollDailyLimit);

  const AdRewardKind(this.key, this.dailyLimit);
  final String key;
  final int dailyLimit;
}

/// 激勵式廣告的獎勵規則。廣告本身由 UI 透過 [RewardedAdGateway] 播放，
/// **看完才呼叫這裡發獎勵**；廣告完全自願，不強迫。
class AdRewardService {
  AdRewardService(this.ctx, this.settings, this.wallet);
  final ServiceContext ctx;
  final SettingsService settings;
  final WalletService wallet;

  String _key(AdRewardKind k) => '${k.key}:${dateKey(ctx.now())}';

  Future<int> remaining(AdRewardKind k, [DatabaseExecutor? ex]) async {
    final used = int.tryParse(await settings.getRaw(_key(k), ex) ?? '') ?? 0;
    return (k.dailyLimit - used).clamp(0, k.dailyLimit);
  }

  Future<void> _consume(DatabaseExecutor ex, AdRewardKind k) async {
    if (await remaining(k, ex) <= 0) throw const UserError('今天的次數用完了，明天再來！');
    final key = _key(k);
    final used = int.tryParse(await settings.getRaw(key, ex) ?? '') ?? 0;
    if (used == 0) {
      await ex.delete('app_settings',
          where: 'key LIKE ? AND key != ?', whereArgs: ['${k.key}:%', key]);
    }
    await settings.setRaw(key, '${used + 1}', ex);
  }

  Future<int> claimCoins() async {
    await ctx.db.transaction((txn) async {
      await _consume(txn, AdRewardKind.coins);
      await wallet.addCoins(txn, CoinSource.ad, adCoinReward, note: '看廣告');
    });
    return adCoinReward;
  }

  /// 這筆交易能不能重抽：今天記的、有掉道具、道具還在背包。
  Future<bool> canReroll(String txnId) async {
    final rows = await ctx.db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
    if (rows.isEmpty) return false;
    final item = rows.first['dropped_item_id'] as String?;
    final created = DateTime.fromMillisecondsSinceEpoch(rows.first['created_at'] as int);
    if (item == null || dateKey(created) != dateKey(ctx.now())) return false;
    final inv = await ctx.db.query('inventory', where: 'item_id = ? AND quantity > 0', whereArgs: [item]);
    return inv.isNotEmpty && await remaining(AdRewardKind.reroll) > 0;
  }

  /// 重抽：收回原本的道具，重新抽一個（盡量不同）。
  Future<ItemDef> reroll(String txnId) async {
    late ItemDef next;
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      if (rows.isEmpty) throw const UserError('找不到這筆紀錄');
      final old = rows.first['dropped_item_id'] as String?;
      final created = DateTime.fromMillisecondsSinceEpoch(rows.first['created_at'] as int);
      if (old == null) throw const UserError('這筆沒有掉道具');
      if (dateKey(created) != dateKey(ctx.now())) throw const UserError('只能重抽今天的道具');
      if (!await removeItemFromInventory(txn, old)) throw const UserError('道具已經用掉了');
      await _consume(txn, AdRewardKind.reroll);
      next = rollItemDrop(ctx.random);
      for (var i = 0; i < 5 && next.id == old; i++) {
        next = rollItemDrop(ctx.random);
      }
      await addItemToInventory(txn, ctx, next.id);
      await txn.update('transactions', {'dropped_item_id': next.id},
          where: 'id = ?', whereArgs: [txnId]);
    });
    return next;
  }
}

/// 播放激勵式廣告。回傳使用者是否看完（拿到獎勵）。
abstract class RewardedAdGateway {
  Future<void> init();
  Future<bool> show();
}

/// 測試用 / 未啟用廣告時：直接視為看完。
class FakeAdGateway implements RewardedAdGateway {
  FakeAdGateway({this.result = true});
  bool result;
  int shown = 0;
  @override
  Future<void> init() async {}
  @override
  Future<bool> show() async {
    shown++;
    return result;
  }
}
