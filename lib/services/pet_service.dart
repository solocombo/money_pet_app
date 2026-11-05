import 'package:sqflite_common/sqlite_api.dart';

import '../data/models.dart';
import '../domain/date_utils.dart';
import '../domain/enums.dart';
import '../domain/evolution_diary.dart';
import '../domain/items.dart';
import '../domain/pet_rules.dart';
import '../domain/tasks.dart';
import 'context.dart';
import 'inventory_service.dart';
import 'settings_service.dart';
import 'task_service.dart';

/// 生病持續天數（之後自動康復）。
const int conditionDurationDays = 5;

/// 離開太久時最多補算幾天（避免一次跑上千天）。
const int maxCatchUpDays = 60;

class PokeResult {
  const PokeResult(this.reaction, {required this.firstToday});
  final String reaction;
  final bool firstToday;
}

class PetService {
  PetService(this.ctx, this.settings, this.tasks);
  final ServiceContext ctx;
  final SettingsService settings;
  final TaskService tasks;

  Future<Pet?> activePet([DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db).rawQuery(
      'SELECT p.*, s.* FROM pets p JOIN pet_status s ON s.pet_id = p.id '
      'WHERE p.is_active = 1 LIMIT 1',
    );
    return rows.isEmpty ? null : Pet.fromRow(rows.first);
  }

  Future<Pet> createPet({required String name, required PetType type}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const UserError('請幫寵物取個名字');
    final id = ctx.newId();
    final now = ctx.now();
    await ctx.db.transaction((txn) async {
      await txn.update('pets', {'is_active': 0});
      await txn.insert('pets', {
        'id': id,
        'name': trimmed,
        'type': type.name,
        'base_san': type.baseSan,
        'is_active': 1,
        'created_at': now.millisecondsSinceEpoch,
      });
      await txn.insert('pet_status', {
        'pet_id': id,
        ...statsToRow(PetStats.initial(type)),
        'last_tick_date': dateKey(now),
        'last_updated': now.millisecondsSinceEpoch,
      });
      await tasks.complete(txn, TaskIds.createPet);
    });
    return (await activePet())!;
  }

  Future<void> rename(String name) async {
    final pet = await activePet();
    if (pet == null || name.trim().isEmpty) return;
    await ctx.db.update('pets', {'name': name.trim()},
        where: 'id = ?', whereArgs: [pet.id]);
  }

  Future<void> saveStats(DatabaseExecutor ex, String petId, PetStats s) =>
      ex.update(
        'pet_status',
        {...statsToRow(s), 'last_updated': ctx.nowMs()},
        where: 'pet_id = ?',
        whereArgs: [petId],
      );

  // ---- 生病 ----

  /// 目前生效中的生病狀態。
  Future<List<PetCondition>> activeConditions([DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db).query('pet_conditions',
        where: 'is_cured = 0 AND expires_at > ?',
        whereArgs: [ctx.nowMs()],
        orderBy: 'started_at');
    return rows.map(PetCondition.fromRow).toList();
  }

  Future<Set<ConditionType>> activeConditionTypes([DatabaseExecutor? ex]) async =>
      {for (final c in await activeConditions(ex)) c.type};

  /// 單一類別超支 → 生病。同一類別同一個月只會觸發一次。回傳是否新觸發。
  Future<ConditionType?> triggerOverspendCondition(
      DatabaseExecutor ex, CategoryGroup group, String month) async {
    final pet = await activePet(ex);
    if (pet == null) return null;
    final exists = await ex.query('pet_conditions',
        where: 'pet_id = ? AND source_group = ? AND source_month = ?',
        whereArgs: [pet.id, group.name, month]);
    if (exists.isNotEmpty) return null;
    final now = ctx.now();
    await ex.insert('pet_conditions', {
      'pet_id': pet.id,
      'condition_type': group.condition.name,
      'source_group': group.name,
      'source_month': month,
      'started_at': now.millisecondsSinceEpoch,
      'expires_at':
          now.add(const Duration(days: conditionDurationDays)).millisecondsSinceEpoch,
    });
    return group.condition;
  }

  /// 治療：把到期時間設成現在，這樣「某天是否生病」的歷史判斷仍然正確。
  Future<void> cureAll(DatabaseExecutor ex) => ex.update(
        'pet_conditions',
        {'is_cured': 1, 'expires_at': ctx.nowMs()},
        where: 'is_cured = 0 AND expires_at > ?',
        whereArgs: [ctx.nowMs()],
      );

  // ---- 每日結算 ----

  /// 把寵物狀態推進到今天：每一個「已經結束的日子」各結算一次。
  /// 啟動 APP、回到前景時呼叫。回傳結算了幾天。
  Future<int> tick() async {
    final pet = await activePet();
    if (pet == null) return 0;
    final today = startOfDay(ctx.now());
    var cursor = parseDateKey(pet.lastTickDate);
    if (!cursor.isBefore(today)) return 0;

    final skip = daysBetween(cursor, today) - maxCatchUpDays;
    if (skip > 0) cursor = DateTime(cursor.year, cursor.month, cursor.day + skip);

    final s = await settings.load();
    var stats = pet.stats;
    var days = 0;
    await ctx.db.transaction((txn) async {
      while (cursor.isBefore(today)) {
        final dayCtx = await _dayContext(txn, cursor, s.easyMode);
        final before = stats;
        stats = tickDay(stats, dayCtx);
        await _writeDiary(txn, pet, cursor, before, stats, dayCtx);
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
        days++;
      }
      await saveStats(txn, pet.id, stats);
      await txn.update('pet_status', {'last_tick_date': dateKey(today)},
          where: 'pet_id = ?', whereArgs: [pet.id]);
    });
    return days;
  }

  Future<DayContext> _dayContext(
      DatabaseExecutor ex, DateTime day, bool easyMode) async {
    final start = day.millisecondsSinceEpoch;
    final end = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
    final noSpend = (await ex.query('no_spend_days',
            where: 'date = ?', whereArgs: [dateKey(day)]))
        .isNotEmpty;
    final txCount = await sumInt(ex,
        'SELECT COUNT(*) FROM transactions WHERE occurred_at >= ? AND occurred_at < ?',
        [start, end]);
    final condRows = await ex.query('pet_conditions',
        where: 'started_at < ? AND expires_at > ?', whereArgs: [end, start]);
    return DayContext(
      noSpendCheckIn: noSpend,
      recorded: noSpend || txCount > 0,
      easyMode: easyMode,
      conditions: {
        for (final r in condRows) PetCondition.fromRow(r).type,
      },
    );
  }

  Future<void> _writeDiary(DatabaseExecutor ex, Pet pet, DateTime day,
      PetStats before, PetStats after, DayContext dc) async {
    final start = day.millisecondsSinceEpoch;
    final end = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
    final rows = await ex.rawQuery(
      "SELECT category, SUM(amount) AS s, COUNT(*) AS n FROM transactions WHERE type = 'expense' "
      'AND occurred_at >= ? AND occurred_at < ? GROUP BY category ORDER BY s DESC',
      [start, end],
    );
    var total = 0;
    var count = 0;
    for (final r in rows) {
      total += (r['s'] as num).toInt();
      count += r['n'] as int;
    }
    final entry = writeDiary(DiaryInput(
      date: day,
      petName: pet.name,
      stats: after,
      expenseTotal: total,
      expenseCount: count,
      noSpend: dc.noSpendCheckIn,
      sick: dc.conditions.isNotEmpty,
      topCategory: rows.isEmpty ? null : Category.tryParse(rows.first['category'] as String),
      becameInsane: !before.isInsane && after.isInsane,
      recovered: before.isInsane && !after.isInsane,
    ));
    await ex.insert(
      'pet_diary',
      {'pet_id': pet.id, 'date': dateKey(day), 'text': entry.text, 'mood': entry.mood.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 最新的日記在前。
  Future<List<(String, DiaryEntry)>> diary({int limit = 60}) async {
    final pet = await activePet();
    if (pet == null) return const [];
    final rows = await ctx.db.query('pet_diary',
        where: 'pet_id = ?', whereArgs: [pet.id], orderBy: 'date DESC', limit: limit);
    return [
      for (final r in rows)
        (
          r['date'] as String,
          DiaryEntry(r['text'] as String,
              enumByName(DiaryMood.values, r['mood'] as String, DiaryMood.calm)),
        ),
    ];
  }

  // ---- 進化 ----

  Future<List<String>> evolutionBlockersFor(Pet pet) async => evolutionBlockers(
      stats: pet.stats, createdAt: pet.createdAt, now: ctx.now(), stage: pet.stage);

  /// 進化：換外型、San 上限 +10。
  Future<EvolvedForm> evolve() async {
    late EvolvedForm form;
    await ctx.db.transaction((txn) async {
      final pet = await activePet(txn);
      if (pet == null) throw const UserError('還沒有寵物');
      final blockers = evolutionBlockers(
          stats: pet.stats, createdAt: pet.createdAt, now: ctx.now(), stage: pet.stage);
      if (blockers.isNotEmpty) throw UserError(blockers.join('、'));
      form = evolvedForms[pet.type]!;
      await txn.update(
        'pets',
        {
          'stage': 1,
          'evolved_at': ctx.nowMs(),
          'base_san': pet.stats.baseSan + evolutionSanBonus,
        },
        where: 'id = ?',
        whereArgs: [pet.id],
      );
    });
    return form;
  }

  // ---- 互動 ----

  Future<PokeResult> poke() async {
    final pet = await activePet();
    if (pet == null) throw const UserError('還沒有寵物');
    var first = false;
    await ctx.db.transaction((txn) async {
      first = await tasks.complete(txn, TaskIds.dailyPoke);
      // 每天第一次戳戳心情 +2；之後只有反應，避免刷屬性。
      if (first && !pet.stats.isInsane) {
        await saveStats(txn, pet.id,
            pet.stats.copyWith(mood: (pet.stats.mood + 2).clamp(0, 100).toDouble()));
      }
    });
    final pool = pet.stats.isInsane ? insanePokeReactions : pokeReactions;
    return PokeResult(pool[ctx.random.nextInt(pool.length)], firstToday: first);
  }

  Future<ItemUseResult> useItem(String itemId) async {
    final item = itemById(itemId);
    if (item == null) throw const UserError('找不到這個道具');
    late ItemUseResult result;
    await ctx.db.transaction((txn) async {
      final pet = await activePet(txn);
      if (pet == null) throw const UserError('還沒有寵物');
      final conditions = await activeConditionTypes(txn);
      result = applyItem(pet.stats, item, conditions);
      if (item.effect == ItemEffect.cure && !result.curesConditions) {
        // 沒生病就不消耗藥。
        return;
      }
      if (!await removeItemFromInventory(txn, itemId)) {
        throw const UserError('背包裡沒有這個道具');
      }
      if (result.curesConditions) await cureAll(txn);
      await saveStats(txn, pet.id, result.stats);
    });
    return result;
  }
}
