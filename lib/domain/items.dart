import 'dart:math';

import 'enums.dart';

/// 道具使用後的效果種類。
enum ItemEffect {
  /// 提升某個屬性。
  attribute,

  /// 治療所有生病狀態。
  cure,
}

class ItemDef {
  const ItemDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.rarity,
    required this.description,
    this.effect = ItemEffect.attribute,
    this.attribute,
    this.value = 0,
    this.extraEffects = const {},
    this.craftedOnly = false,
  });

  /// 穩定 id，會存進資料庫，**不可更改**。
  final String id;
  final String name;
  final String emoji;
  final Rarity rarity;
  final String description;
  final ItemEffect effect;
  final PetAttribute? attribute;
  final int value;

  /// 成品道具的額外效果（主效果之外的其他屬性）。
  final Map<PetAttribute, int> extraEffects;

  /// 只能靠合成取得：不會掉落、商店不賣。
  final bool craftedOnly;

  /// 所有屬性效果（主效果在前）。
  Map<PetAttribute, int> get effects => {
        ?attribute: value,
        ...extraEffects,
      };

  /// 商店售價（金幣）。
  int get shopPrice => switch (rarity) {
        Rarity.common => 30,
        Rarity.rare => 80,
        Rarity.epic => 200,
        Rarity.legendary => 600,
      };

  /// 賣回價格（金幣），約為售價三分之一。
  int get sellPrice => shopPrice ~/ 3;

  String get effectText => switch (effect) {
        ItemEffect.cure => '治療所有生病狀態',
        ItemEffect.attribute =>
          effects.entries.map((e) => '${e.key.label} +${e.value}').join('、'),
      };
}

/// 依稀有度給的基準效果值。智慧值只增不減，所以給比較少。
int _v(Rarity r, {bool wisdom = false}) {
  final base = switch (r) {
    Rarity.common => 5,
    Rarity.rare => 10,
    Rarity.epic => 20,
    Rarity.legendary => 35,
  };
  return wisdom ? (base / 2).ceil() : base;
}

ItemDef _attr(String id, String name, String emoji, Rarity r, PetAttribute a,
        String desc) =>
    ItemDef(
      id: id,
      name: name,
      emoji: emoji,
      rarity: r,
      description: desc,
      attribute: a,
      value: _v(r, wisdom: a == PetAttribute.wisdom),
    );

/// MVP 道具清單。合成系統上線前，所有食材都可以直接使用。
final List<ItemDef> itemCatalog = List.unmodifiable([
  // 飽食
  _attr('onigiri', '飯糰', '🍙', Rarity.common, PetAttribute.fullness, '便利商店的好朋友。'),
  _attr('beef_noodle', '牛肉麵', '🍜', Rarity.rare, PetAttribute.fullness, '湯頭濃郁，吃完很滿足。'),
  _attr('unagi_don', '鰻魚飯', '🍱', Rarity.epic, PetAttribute.fullness, '一年吃一次的奢侈。'),
  _attr('golden_shrimp', '黃金炸蝦', '🍤', Rarity.legendary, PetAttribute.fullness, '傳說中的炸蝦，好像在對你眨眼。'),
  // 健康
  _attr('vitamin', '維他命', '💊', Rarity.common, PetAttribute.health, '每天一顆。'),
  _attr('fruit_juice', '綜合果汁', '🧃', Rarity.rare, PetAttribute.health, '現打的，沒加糖。'),
  _attr('chicken_soup', '人蔘雞湯', '🍲', Rarity.epic, PetAttribute.health, '阿嬤的味道。'),
  _attr('elixir', '仙丹', '🔮', Rarity.legendary, PetAttribute.health, '來源不明，但很有效。'),
  // 整潔
  _attr('soap', '肥皂', '🧼', Rarity.common, PetAttribute.cleanliness, '樸實無華。'),
  _attr('bath_bomb', '泡泡浴球', '🫧', Rarity.rare, PetAttribute.cleanliness, '會冒出彩色泡泡。'),
  _attr('candle', '香氛蠟燭', '🕯️', Rarity.epic, PetAttribute.cleanliness, '房間變得好香。'),
  _attr('rainbow_shampoo', '彩虹洗髮精', '🌈', Rarity.legendary, PetAttribute.cleanliness, '洗完毛會發光。'),
  // 心情
  _attr('teaser', '逗貓棒', '🪶', Rarity.common, PetAttribute.mood, '百玩不膩。'),
  _attr('yarn', '毛線球', '🧶', Rarity.rare, PetAttribute.mood, '滾來滾去。'),
  _attr('game_console', '遊戲機', '🎮', Rarity.epic, PetAttribute.mood, '只能玩一小時喔。'),
  _attr('star_projector', '星空投影燈', '🌌', Rarity.legendary, PetAttribute.mood, '整片銀河都在天花板上。'),
  // 智慧
  _attr('sticky_note', '便條紙', '📝', Rarity.common, PetAttribute.wisdom, '寫下今天學到的事。'),
  _attr('picture_book', '繪本', '📖', Rarity.rare, PetAttribute.wisdom, '圖比字多。'),
  _attr('encyclopedia', '百科全書', '📚', Rarity.epic, PetAttribute.wisdom, '厚到可以當枕頭。'),
  _attr('philosopher_stone', '賢者之石', '💎', Rarity.legendary, PetAttribute.wisdom, '據說能理解一切。'),
  // 理智
  _attr('cocoa', '熱可可', '☕', Rarity.common, PetAttribute.san, '暖暖的，心也定了。'),
  _attr('lavender_tea', '薰衣草茶', '🍵', Rarity.rare, PetAttribute.san, '深呼吸。'),
  _attr('music_box', '安眠音樂盒', '🎶', Rarity.epic, PetAttribute.san, '叮叮咚咚，一切都會好的。'),
  _attr('elder_charm', '舊日護符', '🧿', Rarity.legendary, PetAttribute.san, '刻著看不懂的文字。最好別看太久。'),
  // 治療
  const ItemDef(
    id: 'cold_medicine',
    name: '感冒藥',
    emoji: '🩹',
    rarity: Rarity.rare,
    description: '吃了就會好起來。',
    effect: ItemEffect.cure,
  ),
  ..._craftedItems,
  const ItemDef(
    id: 'panacea',
    name: '萬靈藥',
    emoji: '⚗️',
    rarity: Rarity.epic,
    description: '什麼病都能治。',
    effect: ItemEffect.cure,
  ),
]);

/// 合成成品（只能合成取得）。
const List<ItemDef> _craftedItems = [
  ItemDef(
    id: 'bento', name: '元氣便當', emoji: '🍱', rarity: Rarity.rare, craftedOnly: true,
    description: '自己做的最好吃。',
    attribute: PetAttribute.fullness, value: 15, extraEffects: {PetAttribute.health: 5},
  ),
  ItemDef(
    id: 'deluxe_set', name: '豪華定食', emoji: '🍛', rarity: Rarity.epic, craftedOnly: true,
    description: '主菜、湯、飲料一次到位。',
    attribute: PetAttribute.fullness, value: 25,
    extraEffects: {PetAttribute.health: 10, PetAttribute.mood: 5},
  ),
  ItemDef(
    id: 'spa_set', name: '香氛泡澡組', emoji: '🛁', rarity: Rarity.epic, craftedOnly: true,
    description: '泡完整個人都亮了。',
    attribute: PetAttribute.cleanliness, value: 25, extraEffects: {PetAttribute.mood: 5},
  ),
  ItemDef(
    id: 'party_box', name: '派對盒', emoji: '🎉', rarity: Rarity.epic, craftedOnly: true,
    description: '打開會噴彩帶。',
    attribute: PetAttribute.mood, value: 25,
  ),
  ItemDef(
    id: 'study_plan', name: '讀書計畫', emoji: '🗓️', rarity: Rarity.rare, craftedOnly: true,
    description: '把便條紙整理成一份計畫。',
    attribute: PetAttribute.wisdom, value: 8,
  ),
  ItemDef(
    id: 'calming_sachet', name: '安神香包', emoji: '👝', rarity: Rarity.epic, craftedOnly: true,
    description: '聞了會想睡覺。',
    attribute: PetAttribute.san, value: 25,
  ),
  ItemDef(
    id: 'home_remedy', name: '自製感冒藥', emoji: '🫖', rarity: Rarity.rare, craftedOnly: true,
    description: '維他命配果汁，阿嬤說有效。',
    effect: ItemEffect.cure,
  ),
  ItemDef(
    id: 'feast', name: '全家福大餐', emoji: '🍽️', rarity: Rarity.legendary, craftedOnly: true,
    description: '只有聰明的寵物才知道怎麼做。',
    attribute: PetAttribute.fullness, value: 30,
    extraEffects: {PetAttribute.health: 20, PetAttribute.mood: 20, PetAttribute.cleanliness: 10},
  ),
];

final Map<String, ItemDef> _byId = {for (final i in itemCatalog) i.id: i};

ItemDef? itemById(String id) => _byId[id];

/// 依稀有度權重抽一個道具。金額大小**不影響**結果（避免鼓勵消費）。
ItemDef rollItemDrop(Random random) {
  final rarity = rollRarity(random);
  final pool =
      itemCatalog.where((i) => i.rarity == rarity && !i.craftedOnly).toList();
  return pool[random.nextInt(pool.length)];
}

Rarity rollRarity(Random random) {
  final total = Rarity.values.fold<int>(0, (s, r) => s + r.dropWeight);
  var roll = random.nextInt(total);
  for (final r in Rarity.values) {
    if (roll < r.dropWeight) return r;
    roll -= r.dropWeight;
  }
  return Rarity.common;
}
