// 產生 UI 截圖到 docs/screenshots/。只在需要時手動執行：
//
//   SCREENSHOTS=1 flutter test --update-goldens test/screenshots/
//
// 需要系統有中文字型（文泉驛正黑）與 Noto Color Emoji。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/services/app_services.dart';
import 'package:money_pet_app/state/providers.dart';
import 'package:money_pet_app/ui/app.dart';

import '../helpers.dart';
import '../widget/app_flow_test.dart' show makeWidgetServices, settle;

final _flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
String get _mf => '$_flutterRoot/bin/cache/artifacts/material_fonts';

Map<String, List<String>> get _fonts => {
  'MaterialIcons': ['$_mf/MaterialIcons-Regular.otf'],
  'Roboto': [
    '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
  ],
    };

Future<void> _loadFonts() async {
  for (final e in _fonts.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

Future<AppServices> _seed(FakeClock clock) async {
  final s = await makeWidgetServices(clock);
  await s.settings.update((x) => x.copyWith(onboardingDone: true));
  await s.pets.createPet(name: '小狐', type: PetType.fox);
  await s.ledger.setBudget('2026-05', null, 20000);
  await s.ledger.setBudget('2026-05', CategoryGroup.food, 6000);
  await s.ledger.setBudget('2026-05', CategoryGroup.entertainment, 2000);
  await s.rewards.addReward('吃一頓大餐', 5000);
  await s.rewards.addReward('買新遊戲', 15000);
  await s.rewards.addGoal(name: '這週自己帶便當三次', ptRewardDeci: 300, deadline: DateTime(2026, 5, 17));
  await s.bills.savePaymentMethod(name: '玉山 Pi 卡', type: PaymentType.creditCard, creditLimit: 50000, billingDay: 20, dueDay: 5);
  await s.bills.saveBill(
      name: 'Netflix', type: BillType.subscription, amount: 390, dueDay: 12,
      remindDaysBefore: 3, recurrence: Recurrence.monthly, category: Category.subscription);
  await s.assets.addAccount('台新銀行', AssetType.bank, 85000);
  await s.ledger.addIncome(category: IncomeCategory.salary, amount: 32000, occurredAt: DateTime(2026, 5, 5, 10));
  await s.ledger.addExpense(category: Category.dining, amount: 120, savedAmount: 12, note: '牛肉麵', occurredAt: DateTime(2026, 5, 9, 12));
  await s.ledger.addExpense(category: Category.drinks, amount: 65, occurredAt: DateTime(2026, 5, 9, 15));
  await s.ledger.addExpense(category: Category.publicTransport, amount: 30, occurredAt: DateTime(2026, 5, 10, 8));
  await s.ledger.addExpense(category: Category.books, amount: 380, savedAmount: 38, note: '理財入門', occurredAt: DateTime(2026, 5, 10, 11));
  await s.ctx.db.rawInsert('INSERT INTO inventory VALUES(?, ?) ON CONFLICT(item_id) DO UPDATE SET quantity = excluded.quantity', ['unagi_don', 1]);
  await s.ctx.db.rawInsert('INSERT INTO inventory VALUES(?, ?) ON CONFLICT(item_id) DO UPDATE SET quantity = excluded.quantity', ['onigiri', 3]);
  await s.ctx.db.rawInsert('INSERT INTO inventory VALUES(?, ?) ON CONFLICT(item_id) DO UPDATE SET quantity = excluded.quantity', ['vitamin', 1]);
  await s.ledger.addExpense(category: Category.leisure, amount: 450, occurredAt: DateTime(2026, 5, 3, 20));
  await s.ledger.addExpense(category: Category.dailyGoods, amount: 260, occurredAt: DateTime(2026, 5, 4, 19));
  await s.ledger.addExpense(category: Category.dining, amount: 3200, occurredAt: DateTime(2026, 4, 12, 12));
  await s.ledger.addIncome(category: IncomeCategory.salary, amount: 32000, occurredAt: DateTime(2026, 4, 5, 10));
  await s.ctx.db.rawInsert('INSERT INTO inventory VALUES(?, ?) ON CONFLICT(item_id) DO UPDATE SET quantity = excluded.quantity', ['lavender_tea', 2]);
  await s.ctx.db.insert('item_collection', {'item_id': 'unagi_don', 'first_obtained_at': 0});
  await s.ctx.db.insert('item_collection', {'item_id': 'lavender_tea', 'first_obtained_at': 0});
  await s.tasks.completeAndClaim('daily_check_in');
  return s;
}

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';

  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
    if (enabled) await _loadFonts();
  });

  Future<void> shoot(WidgetTester t, String name, {Future<void> Function()? before}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final clock = FakeClock(DateTime(2026, 5, 10, 12));
    final services = (await t.runAsync(() => _seed(clock)))!;
    await t.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const MoneyPetApp(),
    ));
    await settle(t);
    await before?.call();
    await settle(t);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/$name.png'));
  }

  testWidgets('01 首頁', (t) => shoot(t, '01_home'), skip: !enabled);
  testWidgets('02 記帳', (t) => shoot(t, '02_ledger', before: () => t.tap(find.text('記帳').last)), skip: !enabled);
  testWidgets('03 記一筆', (t) => shoot(t, '03_add', before: () => t.tap(find.text('記一筆'))), skip: !enabled);
  testWidgets('04 商店', (t) => shoot(t, '04_shop', before: () async {
        await t.tap(find.text('道具').last);
        await settle(t);
        await t.tap(find.text('商店'));
      }), skip: !enabled);
  testWidgets('05 圖鑑', (t) => shoot(t, '05_collection', before: () async {
        await t.tap(find.text('道具').last);
        await settle(t);
        await t.tap(find.text('圖鑑'));
      }), skip: !enabled);
  testWidgets('06 任務', (t) => shoot(t, '06_tasks', before: () => t.tap(find.text('任務').last)), skip: !enabled);
  testWidgets('07 獎勵櫃', (t) => shoot(t, '07_rewards', before: () async {
        await t.tap(find.text('任務').last);
        await settle(t);
        await t.tap(find.text('獎勵櫃'));
      }), skip: !enabled);
  testWidgets('09 月報表', (t) => shoot(t, '09_report', before: () async {
        await t.tap(find.text('記帳').last);
        await settle(t);
        await t.tap(find.byTooltip('月報表'));
      }), skip: !enabled);
  testWidgets('10 合成', (t) => shoot(t, '10_craft', before: () async {
        await t.tap(find.text('道具').last);
        await settle(t);
        await t.tap(find.text('合成'));
      }), skip: !enabled);
  testWidgets('08 失控', (t) => shoot(t, '08_insane', before: () async {
        final s = ProviderScope.containerOf(t.element(find.byType(NavigationBar))).read(servicesProvider);
        await t.runAsync(() => s.ctx.db.update('pet_status', {'is_insane': 1, 'san': 12, 'insane_streak': 1}));
        ProviderScope.containerOf(t.element(find.byType(NavigationBar))).read(dataVersionProvider.notifier).bump();
      }), skip: !enabled);
}
