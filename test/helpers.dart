import 'dart:math';

import 'package:money_pet_app/data/database.dart';
import 'package:money_pet_app/services/app_services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 可手動撥動的時鐘。
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
  void set(DateTime d) => now = d;
}

/// 每次呼叫回傳指定序列的亂數，用來控制掉落與 San check。
class ScriptedRandom implements Random {
  ScriptedRandom({this.doubles = const [], this.ints = const []});
  final List<double> doubles;
  final List<int> ints;
  int _d = 0;
  int _i = 0;

  @override
  double nextDouble() => doubles.isEmpty ? 0.99 : doubles[_d++ % doubles.length];

  @override
  int nextInt(int max) => ints.isEmpty ? 0 : ints[_i++ % ints.length] % max;

  @override
  bool nextBool() => nextDouble() < 0.5;
}

bool _ffiReady = false;

Future<Database> openTestDb() async {
  if (!_ffiReady) {
    sqfliteFfiInit();
    _ffiReady = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: onConfigureDatabase,
      onCreate: onCreateDatabase,
      onUpgrade: onUpgradeDatabase,
      singleInstance: false,
    ),
  );
}

Future<(AppServices, FakeClock)> makeServices({
  DateTime? start,
  Random? random,
}) async {
  final clock = FakeClock(start ?? DateTime(2026, 5, 10, 12));
  final db = await openTestDb();
  final s = AppServices(db, clock: clock.call, random: random ?? Random(42));
  return (s, clock);
}
