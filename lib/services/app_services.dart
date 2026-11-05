import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../data/database.dart';
import '../domain/pt_rules.dart';
import 'asset_service.dart';
import 'bill_service.dart';
import 'context.dart';
import 'inventory_service.dart';
import 'ledger_service.dart';
import 'pet_service.dart';
import 'reward_service.dart';
import 'settings_service.dart';
import 'task_service.dart';
import 'wallet_service.dart';

/// 啟動時做的事情的結果，給 UI 跳提示。
class StartupReport {
  const StartupReport({
    this.daysTicked = 0,
    this.settlements = const [],
    this.budgetsCarriedOver = false,
  });

  final int daysTicked;
  final List<(String, MonthSettlement, int)> settlements;
  final bool budgetsCarriedOver;
}

/// 所有 service 的容器。
class AppServices {
  AppServices._(this.ctx)
      : settings = SettingsService(ctx),
        wallet = WalletService(ctx) {
    tasks = TaskService(ctx, wallet);
    inventory = InventoryService(ctx, wallet, tasks);
    pets = PetService(ctx, settings, tasks);
    ledger = LedgerService(ctx, settings, wallet, pets, tasks);
    rewards = RewardService(ctx, settings, wallet, tasks);
    assets = AssetService(ctx, tasks);
    bills = BillService(ctx, ledger);
  }

  factory AppServices(Database db, {DateTime Function()? clock, Random? random}) =>
      AppServices._(ServiceContext(db: db, clock: clock, random: random));

  final ServiceContext ctx;
  final SettingsService settings;
  final WalletService wallet;
  late final TaskService tasks;
  late final InventoryService inventory;
  late final PetService pets;
  late final LedgerService ledger;
  late final RewardService rewards;
  late final AssetService assets;
  late final BillService bills;

  /// 啟動 / 回到前景時呼叫：推進寵物時間、沿用預算、結算上個月。
  /// 順序：先沿用預算（影響本月 PT），再結算過去月份，最後推進寵物。
  Future<StartupReport> onAppResume() async {
    final carried = await ledger.carryOverBudgets();
    final settled = await ledger.settlePendingMonths();
    final days = await pets.tick();
    return StartupReport(
      daysTicked: days,
      settlements: settled,
      budgetsCarriedOver: carried,
    );
  }

  /// 危險區：清除所有資料。
  Future<void> clearAllData() async {
    await ctx.db.transaction((txn) async {
      for (final t in allTables) {
        await txn.delete(t);
      }
    });
  }
}
