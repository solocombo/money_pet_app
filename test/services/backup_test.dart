import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_pet_app/domain/enums.dart';
import 'package:money_pet_app/services/backup_service.dart';
import 'package:money_pet_app/services/context.dart';

import '../helpers.dart';

void main() {
  test('匯出 → 清除 → 匯入，資料完全還原', () async {
    final (s, _) = await makeServices(random: ScriptedRandom());
    await s.settings.update((x) => x.copyWith(onboardingDone: true, easyMode: true));
    await s.pets.createPet(name: '小咪', type: PetType.cat);
    await s.ledger.setBudget('2026-05', null, 20000);
    await s.bills.savePaymentMethod(name: '現金', type: PaymentType.cash);
    final pm = (await s.bills.paymentMethods()).single;
    await s.ledger.addExpense(category: Category.dining, amount: 120, savedAmount: 10, paymentMethodId: pm.id, note: '午餐');
    await s.ledger.addIncome(category: IncomeCategory.salary, amount: 30000);
    await s.rewards.addReward('大餐', 5000);
    await s.assets.addAccount('台新', AssetType.bank, 1000);

    final b = BackupService(s.ctx);
    final json = await b.exportJson();
    final pt = await s.wallet.ptBalanceDeci();

    await s.clearAllData();
    expect(await s.pets.activePet(), isNull);

    final r = await b.importJson(json);
    expect(r.rows, greaterThan(5));
    expect((await s.pets.activePet())!.name, '小咪');
    expect(await s.wallet.ptBalanceDeci(), pt);
    expect((await s.ledger.recentTransactions()).length, 2);
    expect((await s.settings.load()).easyMode, isTrue);
    expect((await s.assets.accounts()).single.name, '台新');
    // 外鍵關聯仍正確
    expect((await s.ledger.recentTransactions()).firstWhere((t) => t.isExpense).paymentMethodId, pm.id);
  });

  test('格式錯誤時不動現有資料', () async {
    final (s, _) = await makeServices();
    await s.pets.createPet(name: '小咪', type: PetType.cat);
    final b = BackupService(s.ctx);
    await expectLater(() => b.importJson('not json'), throwsA(isA<UserError>()));
    await expectLater(() => b.importJson(jsonEncode({'format': 'other'})), throwsA(isA<UserError>()));
    await expectLater(() => b.importJson(jsonEncode({'format': backupFormat, 'schemaVersion': 999, 'tables': {}})),
      throwsA(isA<UserError>()),
    );
    expect(await s.pets.activePet(), isNotNull);
  });

  test('CSV：BOM、跳脫逗號與引號、防公式注入', () async {
    final (s, _) = await makeServices(random: ScriptedRandom());
    await s.ledger.addExpense(category: Category.dining, amount: 100, note: '早餐, "蛋餅"');
    await s.ledger.addExpense(category: Category.misc, amount: 50, note: '=SUM(A1)');
    final csv = await BackupService(s.ctx).exportTransactionsCsv();
    expect(csv.startsWith('﻿日期,'), isTrue);
    expect(csv, contains('"早餐, ""蛋餅"""'));
    expect(csv, contains("'=SUM(A1)"));
    expect(csv, contains('支出,餐飲外食,100,0'));
  });
}
