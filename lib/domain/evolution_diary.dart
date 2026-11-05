import 'dart:math';

import 'date_utils.dart';
import 'enums.dart';
import 'pet_rules.dart';

// ---------------------------------------------------------------------------
// 進化
// ---------------------------------------------------------------------------

class EvolvedForm {
  const EvolvedForm(this.title, this.emoji, this.description);
  final String title;
  final String emoji;
  final String description;
}

const Map<PetType, EvolvedForm> evolvedForms = {
  PetType.cat: EvolvedForm('虎王', '🐯', '曾經的小貓，現在是守護錢包的森林之王。'),
  PetType.dog: EvolvedForm('狼王', '🐺', '忠誠依舊，但多了一份不被誘惑的冷靜。'),
  PetType.fox: EvolvedForm('九尾狐', '🦊', '每一條尾巴都代表一次忍住沒亂買。'),
  PetType.bird: EvolvedForm('孔雀', '🦚', '終於敢展開羽毛，自信地面對每一筆帳。'),
};

const int evolutionMinWisdomLevel = 5;
const int evolutionMinAgeDays = 30;
const int evolutionSanBonus = 10;

/// 還差什麼才能進化；空清單代表可以進化。
List<String> evolutionBlockers({
  required PetStats stats,
  required DateTime createdAt,
  required DateTime now,
  required int stage,
}) {
  if (stage > 0) return const ['已經進化過了'];
  final out = <String>[];
  if (stats.wisdomLevel < evolutionMinWisdomLevel) {
    out.add('智慧要 Lv$evolutionMinWisdomLevel（目前 Lv${stats.wisdomLevel}）');
  }
  final age = daysBetween(createdAt, now);
  if (age < evolutionMinAgeDays) {
    out.add('要一起生活 $evolutionMinAgeDays 天（目前 $age 天）');
  }
  if (stats.isInsane) out.add('寵物要先恢復理智');
  return out;
}

// ---------------------------------------------------------------------------
// 日記
// ---------------------------------------------------------------------------

enum DiaryMood {
  happy('😊'),
  calm('🙂'),
  sad('😢'),
  sick('🤒'),
  eerie('🌀');

  const DiaryMood(this.emoji);
  final String emoji;
}

class DiaryInput {
  const DiaryInput({
    required this.date,
    required this.petName,
    required this.stats,
    required this.expenseTotal,
    required this.expenseCount,
    required this.noSpend,
    required this.sick,
    this.topCategory,
    this.becameInsane = false,
    this.recovered = false,
  });

  final DateTime date;
  final String petName;

  /// 這一天結束時的狀態。
  final PetStats stats;
  final int expenseTotal;
  final int expenseCount;
  final bool noSpend;
  final bool sick;
  final Category? topCategory;
  final bool becameInsane;
  final bool recovered;
}

class DiaryEntry {
  const DiaryEntry(this.text, this.mood);
  final String text;
  final DiaryMood mood;
}

/// 依當天情況產生一篇日記。用日期當亂數種子，同一天每次結果相同。
DiaryEntry writeDiary(DiaryInput i) {
  final rng = Random(i.date.year * 10000 + i.date.month * 100 + i.date.day);
  String pick(List<String> l) => l[rng.nextInt(l.length)];
  final s = i.stats;
  final lines = <String>[];
  DiaryMood mood;

  if (s.isInsane) {
    mood = DiaryMood.eerie;
    lines.add(i.becameInsane
        ? pick(['今天有什麼東西碎掉了。我聽見了數字在牆壁裡爬。', '帳本的字開始扭動。我不記得我是誰。'])
        : pick(['……', '黑暗裡有聲音在數錢。一、二、三……', '我一直盯著同一個地方。那裡什麼都沒有。']));
    if (i.expenseCount > 0 || i.noSpend) lines.add(pick(['主人今天有來。好像比較清醒一點了。', '有一道光。是主人的帳本嗎？']));
    return DiaryEntry(lines.join(''), mood);
  }

  if (i.recovered) {
    lines.add(pick(['醒過來了！好像做了一場很長的惡夢。', '腦袋終於清楚了，謝謝主人一直陪著我。']));
  }

  if (i.noSpend) {
    lines.add(pick(['今天主人一毛錢都沒花，好厲害！', '零支出的一天，我們的錢包在微笑。', '主人今天很省，我也跟著少吃一點點。']));
  } else if (i.expenseCount == 0) {
    lines.add(pick(['今天主人沒有記帳……是忘記了嗎？', '等了一整天，帳本都沒有翻開。']));
  } else {
    final cat = i.topCategory;
    final what = cat == null ? '' : '，最多花在${cat.label}';
    lines.add('今天主人記了 ${i.expenseCount} 筆帳$what。');
    if (cat != null) {
      lines.add(switch (cat.group) {
        CategoryGroup.food => pick(['聞到好香的味道！', '我也想吃一口……', '吃飽才有力氣存錢。']),
        CategoryGroup.health => pick(['主人有在照顧身體，好欣慰。', '健康是最好的投資！']),
        CategoryGroup.living => pick(['家裡又多了新東西。', '買東西的時候有想過真的需要嗎？']),
        CategoryGroup.entertainment => pick(['玩得開心嗎？我也想一起去！', '偶爾放鬆一下也不錯。']),
        CategoryGroup.learning => pick(['主人在學新東西，我也要變聰明！', '書的味道好好聞。']),
        CategoryGroup.transport => pick(['今天也辛苦地移動了。', '主人去了哪裡呢？']),
        CategoryGroup.other => pick(['今天有些特別的花費。', '人情世故也是生活的一部分。']),
      });
    }
  }

  if (i.sick) {
    mood = DiaryMood.sick;
    lines.add(pick(['肚子有點不舒服……', '身體懶懶的，好想睡覺。', '好像生病了，希望快點好起來。']));
  } else {
    final low = PetAttribute.decaying.where((a) => s.valueOf(a) < lowAttributeThreshold).toList();
    if (low.isNotEmpty) {
      mood = DiaryMood.sad;
      lines.add(switch (low.first) {
        PetAttribute.fullness => '肚子好餓……',
        PetAttribute.health => '身體有點虛弱。',
        PetAttribute.cleanliness => '身上髒髒的，想洗澡。',
        PetAttribute.mood => '有點寂寞。',
        _ => '有點不太舒服。',
      });
    } else if (s.isSanWarning) {
      mood = DiaryMood.calm;
      lines.add(pick(['最近心裡有點毛毛的。', '總覺得有什麼在角落看著我。']));
    } else if (i.noSpend || PetAttribute.decaying.every((a) => s.valueOf(a) >= 70)) {
      mood = DiaryMood.happy;
      lines.add(pick(['今天是美好的一天！', '最喜歡主人了！', '明天也要一起加油！']));
    } else {
      mood = DiaryMood.calm;
      lines.add(pick(['平凡的一天。', '明天會更好。', '晚安。']));
    }
  }
  return DiaryEntry(lines.join(''), mood);
}

String formatDiaryDate(String key) {
  final d = parseDateKey(key);
  const w = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month}/${d.day}（${w[d.weekday - 1]}）';
}
