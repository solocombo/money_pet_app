import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/data/database.dart';
import 'package:money_pet_app/data/models.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/domain/evolution_diary.dart';
import 'package:money_pet_app/domain/pet_rules.dart';
import 'package:money_pet_app/services/context.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  test('schema v1 → v2 升級保留資料', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('mp');
    final path = '${dir.path}/t.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onConfigure: onConfigureDatabase, onCreate: onCreateDatabase));
    await v1.insert('pets', {'id': 'p1', 'name': '舊貓', 'type': 'cat', 'base_san': 80, 'created_at': 0});
    await v1.close();

    final v2 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: schemaVersion, onConfigure: onConfigureDatabase, onCreate: onCreateDatabase, onUpgrade: onUpgradeDatabase));
    final row = (await v2.query('pets')).single;
    expect(row['name'], '舊貓');
    expect(row['stage'], 0);
    await v2.insert('pet_diary', {'pet_id': 'p1', 'date': '2026-05-01', 'text': 'x', 'mood': 'calm'});
    await v2.close();
    await dir.delete(recursive: true);
  });

  group('日記', () {
    const ok = PetStats(fullness: 80, health: 80, cleanliness: 80, mood: 80, wisdom: 0, san: 80, baseSan: 80);
    DiaryInput input({PetStats stats = ok, int count = 0, bool noSpend = false, bool sick = false,
            Category? top, bool becameInsane = false}) =>
        DiaryInput(
          date: DateTime(2026, 5, 9),
          petName: '小咪',
          stats: stats,
          expenseTotal: count * 100,
          expenseCount: count,
          noSpend: noSpend,
          sick: sick,
          topCategory: top,
          becameInsane: becameInsane,
        );

    test('同一天結果固定', () {
      expect(writeDiary(input(count: 2, top: Category.dining)).text,
          writeDiary(input(count: 2, top: Category.dining)).text);
    });
    test('依情境決定心情', () {
      expect(writeDiary(input(noSpend: true)).mood, DiaryMood.happy);
      expect(writeDiary(input(sick: true, count: 1, top: Category.dining)).mood, DiaryMood.sick);
      expect(writeDiary(input(stats: ok.copyWith(fullness: 10))).mood, DiaryMood.sad);
      expect(writeDiary(input(stats: ok.copyWith(isInsane: true, san: 5), becameInsane: true)).mood, DiaryMood.eerie);
    });
    test('內容提到記帳筆數與類別', () {
      final t = writeDiary(input(count: 3, top: Category.books)).text;
      expect(t, contains('記了 3 筆帳'));
      expect(t, contains('書籍'));
      expect(writeDiary(input()).text, anyOf(contains('沒有記帳'), contains('帳本都沒有翻開')));
    });

    test('每天結算時寫一篇', () async {
      final (s, clock) = await makeServices(random: ScriptedRandom());
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      await s.ledger.addExpense(category: Category.books, amount: 300);
      clock.advance(const Duration(days: 3));
      await s.pets.tick();
      final d = await s.pets.diary();
      expect(d.length, 3);
      expect(d.first.$1, '2026-05-12', reason: '最新在前');
      expect(d.last.$2.text, contains('書籍'));
    });
  });

  group('進化', () {
    test('條件', () {
      const st = PetStats(fullness: 80, health: 80, cleanliness: 80, mood: 80, wisdom: 90, san: 80, baseSan: 80);
      final created = DateTime(2026, 1, 1);
      expect(evolutionBlockers(stats: st, createdAt: created, now: DateTime(2026, 5, 1), stage: 0), isEmpty);
      expect(evolutionBlockers(stats: st.copyWith(wisdom: 50), createdAt: created, now: DateTime(2026, 5, 1), stage: 0),
          [contains('智慧')]);
      expect(evolutionBlockers(stats: st, createdAt: created, now: DateTime(2026, 1, 20), stage: 0), [contains('30 天')]);
      expect(evolutionBlockers(stats: st, createdAt: created, now: DateTime(2026, 5, 1), stage: 1), isNotEmpty);
    });

    test('進化：San 上限 +10，只能一次', () async {
      final (s, clock) = await makeServices();
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      await s.ctx.db.update('pet_status', {'wisdom': 90});
      await expectLater(() => s.pets.evolve(), throwsA(isA<UserError>()), reason: '還沒滿 30 天');
      clock.advance(const Duration(days: 30));
      await s.pets.tick();
      // 30 天沒照顧會失控；模擬有好好照顧
      await s.ctx.db.update('pet_status',
          {'is_insane': 0, 'san': 80, 'fullness': 80, 'health': 80, 'cleanliness': 80, 'mood': 80});
      final f = await s.pets.evolve();
      expect(f.title, '虎王');
      final Pet p = (await s.pets.activePet())!;
      expect(p.isEvolved, isTrue);
      expect(p.stats.baseSan, 90);
      expect(p.stats.sanMax, 100);
      await expectLater(() => s.pets.evolve(), throwsA(isA<UserError>()));
    });
  });
}
