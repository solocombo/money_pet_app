import 'package:sqflite_common/sqlite_api.dart';

import '../domain/date_utils.dart';
import '../domain/items.dart';
import '../domain/shop_rules.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'task_service.dart';
import 'wallet_service.dart';

/// 加道具到背包，並登記到圖鑑。
Future<void> addItemToInventory(
    DatabaseExecutor ex, ServiceContext ctx, String itemId,
    [int qty = 1]) async {
  await ex.rawInsert(
    'INSERT INTO inventory(item_id, quantity) VALUES(?, ?) '
    'ON CONFLICT(item_id) DO UPDATE SET quantity = quantity + excluded.quantity',
    [itemId, qty],
  );
  await ex.insert(
    'item_collection',
    {'item_id': itemId, 'first_obtained_at': ctx.nowMs()},
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

/// 從背包移除；數量不足回傳 false。
Future<bool> removeItemFromInventory(DatabaseExecutor ex, String itemId,
    [int qty = 1]) async {
  final n = await ex.rawUpdate(
    'UPDATE inventory SET quantity = quantity - ? WHERE item_id = ? AND quantity >= ?',
    [qty, itemId, qty],
  );
  if (n == 0) return false;
  await ex.delete('inventory', where: 'item_id = ? AND quantity = 0', whereArgs: [itemId]);
  return true;
}

class InventoryEntry {
  const InventoryEntry(this.item, this.quantity);
  final ItemDef item;
  final int quantity;
}

class ShopSlotState {
  const ShopSlotState(this.slot, {required this.purchased});
  final ShopSlot slot;
  final bool purchased;
}

class InventoryService {
  InventoryService(this.ctx, this.wallet, this.tasks);
  final ServiceContext ctx;
  final WalletService wallet;
  final TaskService tasks;

  Future<List<InventoryEntry>> list() async {
    final rows = await ctx.db.query('inventory', where: 'quantity > 0');
    final out = <InventoryEntry>[];
    for (final r in rows) {
      final item = itemById(r['item_id'] as String);
      if (item != null) out.add(InventoryEntry(item, r['quantity'] as int));
    }
    out.sort((a, b) {
      final r = b.item.rarity.index.compareTo(a.item.rarity.index);
      return r != 0 ? r : a.item.name.compareTo(b.item.name);
    });
    return out;
  }

  Future<int> quantityOf(String itemId, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db)
        .query('inventory', where: 'item_id = ?', whereArgs: [itemId]);
    return rows.isEmpty ? 0 : rows.first['quantity'] as int;
  }

  /// 圖鑑：曾經獲得過的道具 id → 第一次獲得時間。
  Future<Map<String, DateTime>> collection() async {
    final rows = await ctx.db.query('item_collection');
    return {
      for (final r in rows)
        r['item_id'] as String:
            DateTime.fromMillisecondsSinceEpoch(r['first_obtained_at'] as int),
    };
  }

  Future<int> sell(String itemId, {int qty = 1}) async {
    final item = itemById(itemId);
    if (item == null) throw const UserError('找不到這個道具');
    final total = item.sellPrice * qty;
    await ctx.db.transaction((txn) async {
      if (!await removeItemFromInventory(txn, itemId, qty)) {
        throw const UserError('數量不足');
      }
      await wallet.addCoins(txn, CoinSource.sell, total, note: '賣出 ${item.name}');
    });
    return total;
  }

  Future<List<ShopSlotState>> todayShop() async {
    final today = ctx.now();
    final rows = await ctx.db
        .query('shop_purchases', where: 'date = ?', whereArgs: [dateKey(today)]);
    final bought = {for (final r in rows) r['slot'] as int};
    return [
      for (final s in dailyShop(today))
        ShopSlotState(s, purchased: bought.contains(s.slot)),
    ];
  }

  /// 每格商品每天限購一次。
  Future<ItemDef> buy(int slotIndex) async {
    final today = ctx.now();
    final slot = dailyShop(today).firstWhere((s) => s.slot == slotIndex);
    await ctx.db.transaction((txn) async {
      final insane = await sumInt(txn,
          'SELECT COUNT(*) FROM pet_status s JOIN pets p ON p.id = s.pet_id '
          'WHERE p.is_active = 1 AND s.is_insane = 1');
      if (insane > 0) throw const UserError('寵物失控中，商店暫停營業……');
      final exists = await txn.query('shop_purchases',
          where: 'date = ? AND slot = ?', whereArgs: [dateKey(today), slotIndex]);
      if (exists.isNotEmpty) throw const UserError('今天已經買過這個了');
      if (await wallet.coinBalance(txn) < slot.price) {
        throw const UserError('金幣不足');
      }
      await txn.insert('shop_purchases', {
        'date': dateKey(today),
        'slot': slotIndex,
        'item_id': slot.item.id,
        'price': slot.price,
        'purchased_at': ctx.nowMs(),
      });
      await wallet.addCoins(txn, CoinSource.shop, -slot.price,
          note: '購買 ${slot.item.name}');
      await addItemToInventory(txn, ctx, slot.item.id);
      await tasks.complete(txn, TaskIds.firstShop);
    });
    return slot.item;
  }
}
