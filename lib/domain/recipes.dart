import 'items.dart';

class Recipe {
  const Recipe({
    required this.id,
    required this.resultId,
    required this.ingredients,
    this.requiredWisdomLevel = 1,
  });

  /// 穩定 id，**不可更改**。
  final String id;
  final String resultId;

  /// 道具 id → 需要數量。
  final Map<String, int> ingredients;

  /// 智慧等級門檻（Lv4 解鎖特殊合成配方）。
  final int requiredWisdomLevel;

  ItemDef get result => itemById(resultId)!;
}

const List<Recipe> recipes = [
  Recipe(id: 'r_bento', resultId: 'bento', ingredients: {'onigiri': 2, 'vitamin': 1}),
  Recipe(id: 'r_study_plan', resultId: 'study_plan', ingredients: {'sticky_note': 3}),
  Recipe(id: 'r_home_remedy', resultId: 'home_remedy', ingredients: {'vitamin': 2, 'fruit_juice': 1}),
  Recipe(id: 'r_spa_set', resultId: 'spa_set', ingredients: {'soap': 2, 'bath_bomb': 1}),
  Recipe(id: 'r_party_box', resultId: 'party_box', ingredients: {'teaser': 2, 'yarn': 1}),
  Recipe(id: 'r_calming_sachet', resultId: 'calming_sachet', ingredients: {'cocoa': 2, 'lavender_tea': 1}),
  Recipe(
    id: 'r_deluxe_set',
    resultId: 'deluxe_set',
    ingredients: {'beef_noodle': 1, 'fruit_juice': 1, 'onigiri': 1},
  ),
  Recipe(
    id: 'r_feast',
    resultId: 'feast',
    ingredients: {'unagi_don': 1, 'chicken_soup': 1, 'game_console': 1},
    requiredWisdomLevel: 4,
  ),
];

/// 背包數量 → 這個配方最多能做幾份。
int craftableCount(Recipe r, Map<String, int> inventory) {
  var n = 1 << 30;
  for (final e in r.ingredients.entries) {
    final have = inventory[e.key] ?? 0;
    final can = have ~/ e.value;
    if (can < n) n = can;
  }
  return n;
}
