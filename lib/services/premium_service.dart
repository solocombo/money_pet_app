import 'package:sqflite_common/sqlite_api.dart';

import '../domain/items.dart';
import 'context.dart';
import 'inventory_service.dart';
import 'settings_service.dart';

/// 付費進階版（NT$90 買斷）的商品 ID，要和 Play Console / App Store Connect 一致。
const String premiumProductId = 'premium_unlock';

/// 進階版權益（目前已實作的部分）。
const List<String> premiumPerks = [
  '移除廣告：看廣告的獎勵直接領取',
  '無限重抽道具（今天記帳掉的）',
  '每日簽到額外送一個道具',
  '支持開發者繼續做新寵物 ❤️',
];

class PremiumService {
  PremiumService(this.ctx, this.settings);
  final ServiceContext ctx;
  final SettingsService settings;

  static const _key = 'premium';

  Future<bool> isPremium([DatabaseExecutor? ex]) async =>
      await settings.getRaw(_key, ex) == '1';

  /// 購買成功或恢復購買後呼叫。
  Future<void> unlock() => settings.setRaw(_key, '1');

  /// 進階版每日簽到的額外道具。
  Future<ItemDef> grantDailyBonusItem(DatabaseExecutor ex) async {
    final item = rollItemDrop(ctx.random);
    await addItemToInventory(ex, ctx, item.id);
    return item;
  }
}

/// 商店購買的抽象。
abstract class PurchaseGateway {
  /// 商店是否可用（模擬器或沒登入時為 false）。
  Future<bool> isAvailable();

  /// 商店上的價格字串（例如 "NT$90"），查不到為 null。
  Future<String?> price();

  /// 開始購買；結果透過 [onPurchased] 回呼。回傳是否成功開啟購買流程。
  Future<bool> buy();
  Future<void> restore();

  /// 購買或恢復成功時呼叫（main 裡接上 PremiumService.unlock）。
  set onPurchased(Future<void> Function() cb);
}

class FakePurchaseGateway implements PurchaseGateway {
  Future<void> Function()? _cb;
  @override
  set onPurchased(Future<void> Function() cb) => _cb = cb;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> price() async => 'NT\$90';
  @override
  Future<bool> buy() async {
    await _cb?.call();
    return true;
  }

  @override
  Future<void> restore() async => _cb?.call();
}
