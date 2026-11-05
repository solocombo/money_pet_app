import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_pet_app/data/database.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/services/app_services.dart';
import 'package:money_pet_app/state/providers.dart';
import 'package:money_pet_app/ui/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

/// 不開 isolate 的 ffi，才能在 testWidgets 的 fake async 環境下運作。
Future<AppServices> makeWidgetServices(FakeClock clock) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: onConfigureDatabase,
      onCreate: onCreateDatabase,
      singleInstance: false,
    ),
  );
  return AppServices(db, clock: clock.call, random: ScriptedRandom());
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  testWidgets('Onboarding → 記第一筆帳 → 首頁 → 背包有道具', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);

    final clock = FakeClock(DateTime(2026, 5, 10, 12));
    final services = await t.runAsync(() => makeWidgetServices(clock));
    await t.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services!)],
      child: const MoneyPetApp(),
    ));
    await settle(t);

    // 1. 歡迎
    expect(find.text('歡迎來到錢寵'), findsOneWidget);
    await t.tap(find.text('開始'));
    await settle(t);

    // 2. 建立寵物（沒取名會被擋）
    await t.tap(find.text('🦊'));
    await t.tap(find.text('就決定是你了'));
    await settle(t);
    expect(find.text('請幫寵物取個名字'), findsOneWidget);
    await t.enterText(find.byType(TextField), '小狐');
    await t.tap(find.text('就決定是你了'));
    await settle(t);

    // 3. 獎勵櫃：沒設定不能下一步
    expect(find.text('至少設定一個獎勵'), findsOneWidget);
    await t.tap(find.text('新增獎勵'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, '獎勵'), '吃一頓大餐');
    await t.tap(find.text('新增'));
    await settle(t);
    expect(find.text('吃一頓大餐'), findsOneWidget);
    await t.tap(find.text('下一步'));
    await settle(t);

    // 4. 預算
    await t.enterText(find.byType(TextField), '20000');
    await t.tap(find.text('設定'));
    await settle(t);

    // 5. 第一筆帳（含省下金額 → 拿到 PT）
    await t.tap(find.text('記一筆'));
    await settle(t);
    expect(find.text('記一筆'), findsWidgets);
    await t.enterText(find.widgetWithText(TextField, '金額'), '120');
    await t.enterText(find.widgetWithText(TextField, '本次省下金額（選填）'), '20');
    await t.tap(find.text('儲存').first);
    await settle(t);
    expect(find.text('記帳完成！'), findsOneWidget);
    expect(find.textContaining('獲得 飯糰'), findsOneWidget);
    expect(find.text('獲得 2.0 PT'), findsOneWidget);
    await t.tap(find.text('好'));
    await settle(t);

    // 6. 完成
    expect(find.text('準備好了！'), findsOneWidget);
    await t.tap(find.text('開始養寵物'));
    await settle(t);

    // 首頁
    expect(find.text('小狐'), findsOneWidget);
    expect(find.text('⭐ 2.0 PT'), findsWidgets);
    await t.tap(find.text('簽到'));
    await settle(t);
    expect(find.text('已簽到'), findsOneWidget);
    expect(find.text('🪙 20'), findsWidgets);

    // 戳戳
    await t.tap(find.text('🦊'));
    await settle(t);
    expect(find.textContaining('小狐 '), findsWidgets);

    // 背包
    await t.tap(find.text('道具'));
    await settle(t);
    expect(find.text('飯糰 ×1'), findsOneWidget);
    await t.tap(find.text('飯糰 ×1'));
    await settle(t);
    await t.tap(find.text('給寵物使用'));
    await settle(t);
    expect(find.textContaining('飽食 +'), findsOneWidget);

    // 任務頁：新手任務可以領
    await t.tap(find.text('任務').last);
    await settle(t);
    expect(find.text('領取'), findsWidgets);

    // 記帳頁顯示本月
    await t.tap(find.text('記帳').last);
    await settle(t);
    expect(find.text('2026 年 5 月'), findsOneWidget);
    expect(find.text('餐飲外食'), findsWidgets);
  });

  testWidgets('寵物失控時文字變亂碼，關掉選項就恢復', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);

    final clock = FakeClock(DateTime(2026, 5, 10, 12));
    final services = (await t.runAsync(() async {
      final s = await makeWidgetServices(clock);
      await s.settings.update((x) => x.copyWith(onboardingDone: true));
      await s.pets.createPet(name: '小咪', type: PetType.cat);
      await s.ctx.db.update('pet_status', {'is_insane': 1, 'san': 10});
      return s;
    }))!;
    await t.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const MoneyPetApp(),
    ));
    await settle(t);

    expect(find.text('小咪'), findsNothing, reason: '名字被亂碼化');
    expect(find.textContaining('連續記帳 3 天'), findsNothing);

    await t.runAsync(() => services.settings.update((x) => x.copyWith(disableGarble: true)));
    final ctx = t.element(find.byType(NavigationBar));
    ProviderScope.containerOf(ctx).read(dataVersionProvider.notifier).bump();
    await settle(t);
    expect(find.text('小咪'), findsOneWidget);
    expect(find.textContaining('連續記帳 3 天'), findsOneWidget);
  });
}
