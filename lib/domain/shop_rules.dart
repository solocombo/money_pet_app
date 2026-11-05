import 'dart:math';

import 'enums.dart';
import 'items.dart';

class ShopSlot {
  const ShopSlot({
    required this.slot,
    required this.item,
    required this.price,
    required this.isLimited,
  });

  final int slot;
  final ItemDef item;
  final int price;

  /// 每日限定商品：稀有度較高、打 7 折。
  final bool isLimited;
}

const int shopRegularSlots = 3;
const double limitedDiscount = 0.7;

/// 以日期當種子產生當日商店，同一天每次打開都一樣，隔天自動換貨。
List<ShopSlot> dailyShop(DateTime day) {
  final seed = day.year * 10000 + day.month * 100 + day.day;
  final rng = Random(seed);
  final slots = <ShopSlot>[];
  final usedIds = <String>{};

  ItemDef pick(bool Function(ItemDef) filter) {
    final pool =
        itemCatalog.where((i) => filter(i) && !usedIds.contains(i.id)).toList();
    final item = pool[rng.nextInt(pool.length)];
    usedIds.add(item.id);
    return item;
  }

  for (var i = 0; i < shopRegularSlots; i++) {
    final rarity = rollRarity(rng);
    // 一般商品不賣傳說級，留給限定格。
    final r = rarity == Rarity.legendary ? Rarity.epic : rarity;
    final item = pick((it) => it.rarity == r);
    slots.add(ShopSlot(slot: i, item: item, price: item.shopPrice, isLimited: false));
  }

  final limited = pick((it) =>
      it.rarity == Rarity.epic || it.rarity == Rarity.legendary);
  slots.add(ShopSlot(
    slot: shopRegularSlots,
    item: limited,
    price: (limited.shopPrice * limitedDiscount).round(),
    isLimited: true,
  ));
  return slots;
}
