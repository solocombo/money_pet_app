import 'dart:math';

import 'enums.dart';
import 'items.dart';

/// 寵物屬性快照（不可變）。所有計算規則都是純函式，便於測試。
class PetStats {
  const PetStats({
    required this.fullness,
    required this.health,
    required this.cleanliness,
    required this.mood,
    required this.wisdom,
    required this.san,
    required this.baseSan,
    this.isInsane = false,
    this.insaneStreak = 0,
  });

  factory PetStats.initial(PetType type) => PetStats(
        fullness: 80,
        health: 80,
        cleanliness: 80,
        mood: 80,
        wisdom: 0,
        san: type.baseSan.toDouble(),
        baseSan: type.baseSan,
      );

  final double fullness;
  final double health;
  final double cleanliness;
  final double mood;
  final double wisdom;
  final double san;

  /// 該動物種類的初始理智值，用來算 San 上限。
  final int baseSan;

  /// 失控狀態（San < 20）。
  final bool isInsane;

  /// 失控時連續記帳的天數；到 3 天就恢復理智。
  final int insaneStreak;

  int get wisdomLevel => wisdomLevelOf(wisdom);

  /// San 上限 = 初始值 + (智慧等級 - 1) × 5，最高 100。
  double get sanMax => min(100, baseSan + (wisdomLevel - 1) * 5).toDouble();

  bool get isSanWarning => !isInsane && san < sanWarningThreshold;

  double valueOf(PetAttribute a) => switch (a) {
        PetAttribute.fullness => fullness,
        PetAttribute.health => health,
        PetAttribute.cleanliness => cleanliness,
        PetAttribute.mood => mood,
        PetAttribute.wisdom => wisdom,
        PetAttribute.san => san,
      };

  PetStats withValue(PetAttribute a, double v) => switch (a) {
        PetAttribute.fullness => copyWith(fullness: v),
        PetAttribute.health => copyWith(health: v),
        PetAttribute.cleanliness => copyWith(cleanliness: v),
        PetAttribute.mood => copyWith(mood: v),
        PetAttribute.wisdom => copyWith(wisdom: v),
        PetAttribute.san => copyWith(san: v),
      };

  PetStats copyWith({
    double? fullness,
    double? health,
    double? cleanliness,
    double? mood,
    double? wisdom,
    double? san,
    bool? isInsane,
    int? insaneStreak,
  }) =>
      PetStats(
        fullness: fullness ?? this.fullness,
        health: health ?? this.health,
        cleanliness: cleanliness ?? this.cleanliness,
        mood: mood ?? this.mood,
        wisdom: wisdom ?? this.wisdom,
        san: san ?? this.san,
        baseSan: baseSan,
        isInsane: isInsane ?? this.isInsane,
        insaneStreak: insaneStreak ?? this.insaneStreak,
      );

  @override
  String toString() =>
      'PetStats(f:$fullness h:$health c:$cleanliness m:$mood w:$wisdom '
      'san:$san insane:$isInsane streak:$insaneStreak)';
}

const double sanInsaneThreshold = 20;
const double sanWarningThreshold = 40;
const double sanRecoverTo = 40;
const int insaneRecoveryDays = 3;
const double lowAttributeThreshold = 30;
const double medicineDependenceHealthCap = 70;

int wisdomLevelOf(double wisdom) {
  if (wisdom <= 20) return 1;
  if (wisdom <= 40) return 2;
  if (wisdom <= 60) return 3;
  if (wisdom <= 80) return 4;
  return 5;
}

const Map<int, String> wisdomUnlocks = {
  1: '基本戳戳、摸頭',
  2: '餵食動畫升級、寵物主動跑來找你',
  3: '寵物學會把戲、解鎖寵物日記',
  4: '寵物幫你找隱藏道具、解鎖特殊合成配方',
  5: '寵物進化形態解鎖、特殊互動動畫',
};

double _clamp(double v, [double hi = 100]) => v.clamp(0, hi).toDouble();

/// 每日自然下降的基準值。
const Map<PetAttribute, double> baseDailyDecay = {
  PetAttribute.fullness: 15,
  PetAttribute.mood: 10,
  PetAttribute.cleanliness: 8,
  PetAttribute.health: 5,
};

/// 本日無支出時飽食值只下降 7。
const double noSpendFullnessDecay = 7;

/// 失控時每種屬性額外下降的量。
const double insaneExtraDecay = 2;

/// 一天結束時的情境。
class DayContext {
  const DayContext({
    this.noSpendCheckIn = false,
    this.recorded = false,
    this.easyMode = false,
    this.conditions = const {},
  });

  /// 這天有按「本日無支出」。
  final bool noSpendCheckIn;

  /// 這天有記帳或按本日無支出（用於失控恢復的連續天數）。
  final bool recorded;

  /// 輕鬆模式：所有下降速率減半。
  final bool easyMode;

  /// 這天生效中的生病狀態。
  final Set<ConditionType> conditions;
}

/// 結算「一整天」：屬性自然下降 → San 下降 → 失控判定 / 恢復。
PetStats tickDay(PetStats s, DayContext ctx) {
  var out = s;
  final sick = ctx.conditions;

  for (final entry in baseDailyDecay.entries) {
    var decay = entry.value;
    if (entry.key == PetAttribute.fullness && ctx.noSpendCheckIn) {
      decay = noSpendFullnessDecay;
    }
    if (sick.contains(ConditionType.fatigue)) decay *= 1.5;
    if (entry.key == PetAttribute.mood &&
        sick.contains(ConditionType.overindulgence)) {
      decay *= 2;
    }
    if (ctx.easyMode) decay *= 0.5;
    if (s.isInsane) decay += insaneExtraDecay;
    out = out.withValue(entry.key, _clamp(out.valueOf(entry.key) - decay));
  }
  if (sick.contains(ConditionType.medicineDependence)) {
    out = out.copyWith(health: min(out.health, medicineDependenceHealthCap));
  }

  // San 下降：多個條件取最大值，不疊加（避免雪崩懲罰）。
  var sanLoss = 0.0;
  final anyLow = PetAttribute.decaying
      .any((a) => out.valueOf(a) < lowAttributeThreshold);
  if (anyLow) sanLoss = max(sanLoss, 3);
  if (sick.isNotEmpty) sanLoss = max(sanLoss, 5);
  out = out.copyWith(san: _clamp(out.san - sanLoss, out.sanMax));

  // 失控中：連續記帳 3 天恢復理智。
  if (s.isInsane) {
    final streak = ctx.recorded ? s.insaneStreak + 1 : 0;
    if (streak >= insaneRecoveryDays) {
      return out.copyWith(
        isInsane: false,
        insaneStreak: 0,
        san: max(out.san, min(sanRecoverTo, out.sanMax)),
      );
    }
    return out.copyWith(insaneStreak: streak);
  }
  if (out.san < sanInsaneThreshold) {
    return out.copyWith(isInsane: true, insaneStreak: 0);
  }
  return out;
}

/// 記一筆支出時，對應屬性固定小幅提升（與金額無關，避免鼓勵消費）。
const double recordAttributeBonus = 3;

PetStats applyRecordBonus(PetStats s, Category category) {
  final attr = category.group.attribute;
  if (attr == null) return s;
  return _addAttribute(s, attr, recordAttributeBonus, const {});
}

PetStats _addAttribute(
    PetStats s, PetAttribute a, double delta, Set<ConditionType> sick) {
  var cap = 100.0;
  if (a == PetAttribute.san) cap = s.sanMax;
  if (a == PetAttribute.health &&
      sick.contains(ConditionType.medicineDependence)) {
    cap = medicineDependenceHealthCap;
  }
  var next = s.withValue(a, _clamp(s.valueOf(a) + delta, cap));
  // 理智值回到 40 以上就脫離失控。
  if (a == PetAttribute.san && next.isInsane && next.san >= sanRecoverTo) {
    next = next.copyWith(isInsane: false, insaneStreak: 0);
  }
  return next;
}

class ItemUseResult {
  const ItemUseResult(this.stats, this.message, {this.curesConditions = false});
  final PetStats stats;
  final String message;
  final bool curesConditions;
}

/// 使用道具，套用生病狀態的修正。
ItemUseResult applyItem(
    PetStats s, ItemDef item, Set<ConditionType> conditions) {
  if (item.effect == ItemEffect.cure) {
    if (conditions.isEmpty) {
      return ItemUseResult(s, '寵物現在沒有生病喔', curesConditions: false);
    }
    return ItemUseResult(s, '寵物康復了！', curesConditions: true);
  }

  final attr = item.attribute!;
  var delta = item.value.toDouble();
  final notes = <String>[];
  if (conditions.contains(ConditionType.gastroenteritis)) {
    delta /= 2;
    notes.add('腸胃炎：效果減半');
  }
  if (attr == PetAttribute.cleanliness &&
      conditions.contains(ConditionType.shopaholic)) {
    delta = -delta;
    notes.add('購物狂：整潔值不升反降');
  }
  final next = _addAttribute(s, attr, delta, conditions);
  final actual = next.valueOf(attr) - s.valueOf(attr);
  final sign = actual >= 0 ? '+' : '';
  final msg = StringBuffer('${attr.label} $sign${actual.toStringAsFixed(0)}');
  if (notes.isNotEmpty) msg.write('（${notes.join('、')}）');
  return ItemUseResult(next, msg.toString());
}

/// San check 的觸發原因。
enum SanTrigger {
  impulse('衝動消費'),
  lateNight('深夜記帳'),
  repeatedCategory('同類別記太多筆'),
  budgetRunningOut('預算快見底');

  const SanTrigger(this.label);
  final String label;
}

class SanCheckInput {
  const SanCheckInput({
    required this.amount,
    required this.occurredAt,
    required this.sameCategoryCountToday,
    required this.impulseThreshold,
    required this.repeatThreshold,
    this.monthBudget,
    this.monthSpentIncludingThis = 0,
  });

  final int amount;
  final DateTime occurredAt;

  /// 含這筆在內，同類別今天記了幾筆。
  final int sameCategoryCountToday;
  final int impulseThreshold;
  final int repeatThreshold;
  final int? monthBudget;
  final int monthSpentIncludingThis;
}

/// 找出這筆支出觸發了哪些 San check 條件。
List<SanTrigger> sanTriggers(SanCheckInput i) {
  final out = <SanTrigger>[];
  if (i.impulseThreshold > 0 && i.amount > i.impulseThreshold) {
    out.add(SanTrigger.impulse);
  }
  // 凌晨 0:00–4:59 視為深夜。
  if (i.occurredAt.hour < 5) out.add(SanTrigger.lateNight);
  if (i.repeatThreshold > 0 && i.sameCategoryCountToday > i.repeatThreshold) {
    out.add(SanTrigger.repeatedCategory);
  }
  final budget = i.monthBudget;
  if (budget != null && budget > 0) {
    final d = i.occurredAt;
    final daysInMonth = DateTime(d.year, d.month + 1, 0).day;
    final daysLeft = daysInMonth - d.day;
    if (i.monthSpentIncludingThis >= budget * 0.9 && daysLeft >= 7) {
      out.add(SanTrigger.budgetRunningOut);
    }
  }
  return out;
}

/// San check 失敗機率：基礎 50%，每個智慧等級降 5%（Lv5 為 30%）。
double sanCheckFailChance(int wisdomLevel) => 0.5 - 0.05 * (wisdomLevel - 1);

const double sanCheckPenalty = 10;

class SanCheckResult {
  const SanCheckResult(this.stats, {required this.triggered, required this.failed});
  final PetStats stats;
  final List<SanTrigger> triggered;
  final bool failed;
}

/// 有觸發條件就擲一次（多個條件只擲一次，不疊加）。
SanCheckResult runSanCheck(PetStats s, List<SanTrigger> triggers, Random rng) {
  if (triggers.isEmpty) {
    return SanCheckResult(s, triggered: triggers, failed: false);
  }
  final failed = rng.nextDouble() < sanCheckFailChance(s.wisdomLevel);
  if (!failed) return SanCheckResult(s, triggered: triggers, failed: false);
  var next = s.copyWith(san: _clamp(s.san - sanCheckPenalty, s.sanMax));
  if (!next.isInsane && next.san < sanInsaneThreshold) {
    next = next.copyWith(isInsane: true, insaneStreak: 0);
  }
  return SanCheckResult(next, triggered: triggers, failed: true);
}

/// 戳寵物的隨機反應。
const List<String> pokeReactions = [
  '翻了個身 🙃',
  '打了個噴嚏 🤧',
  '跑開了 💨',
  '蹭蹭你的手 🥰',
  '假裝沒看到 😑',
  '原地轉圈圈 🌀',
  '打了個大哈欠 🥱',
  '開心地跳起來 ✨',
];

const List<String> insanePokeReactions = [
  '……',
  '牠的眼睛裡什麼都沒有。',
  '牠只是靜靜地呼吸著。',
  '你好像聽到很遠的地方有人在低語。',
];
