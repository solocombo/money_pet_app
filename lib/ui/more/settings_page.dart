import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../domain/date_utils.dart';
import '../../domain/pt_rules.dart';
import '../../platform/file_io.dart';
import '../../services/backup_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: AsyncView(ref.watch(settingsProvider), builder: (s) => _Body(s: s)),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.s});
  final AppSettings s;

  Future<void> _set(BuildContext context, WidgetRef ref, AppSettings Function(AppSettings) f) =>
      runAction(context, ref, (svc) => svc.settings.update(f));

  Future<void> _percent(BuildContext context, WidgetRef ref,
      {required String title, required double current, required AppSettings Function(AppSettings, double) apply}) async {
    final v = await promptText(context, title: title, label: '百分比（%）', initial: (current * 100).round().toString(), numeric: true);
    final n = parseIntOrNull(v);
    if (n == null || !context.mounted) return;
    await _set(context, ref, (x) => apply(x, n.clamp(1, 500) / 100));
  }

  Future<void> _int(BuildContext context, WidgetRef ref,
      {required String title, String? label, required int current, int min = 0, int max = 1 << 30,
      required AppSettings Function(AppSettings, int) apply}) async {
    final v = await promptText(context, title: title, label: label, initial: current.toString(), numeric: true);
    final n = parseIntOrNull(v);
    if (n == null || !context.mounted) return;
    await _set(context, ref, (x) => apply(x, n.clamp(min, max)));
  }

  Future<void> _rate(BuildContext context, WidgetRef ref,
      {required String title, required double current, required PtRates Function(PtRates, double) apply}) async {
    final v = await promptText(context, title: title, label: '比率（例如 0.1）', initial: current.toString(), decimal: true);
    final d = v == null ? null : double.tryParse(v);
    if (d == null || d < 0 || d > 1 || !context.mounted) return;
    await _set(context, ref, (x) => x.copyWith(ptRates: apply(x.ptRates, d)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = s.ptRates;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      const SectionTitle('財務設定'),
      Card(
        child: Column(children: [
          ListTile(
            title: const Text('預算超支懲罰閾值'),
            subtitle: const Text('類別花費超過預算多少 % 會讓寵物生病'),
            trailing: Text('${(s.overspendThreshold * 100).round()}%'),
            onTap: () => _percent(context, ref,
                title: '超支懲罰閾值', current: s.overspendThreshold, apply: (x, v) => x.copyWith(overspendThreshold: v)),
          ),
          ListTile(
            title: const Text('信用卡警戒額度'),
            subtitle: const Text('本期刷卡超過額度多少 % 會提醒'),
            trailing: Text('${(s.creditWarnRatio * 100).round()}%'),
            onTap: () => _percent(context, ref,
                title: '信用卡警戒額度', current: s.creditWarnRatio, apply: (x, v) => x.copyWith(creditWarnRatio: v.clamp(0.01, 1.0))),
          ),
          SwitchListTile(
            title: const Text('每週從星期一開始'),
            subtitle: Text(s.weekStartsMonday ? '星期一' : '星期日'),
            value: s.weekStartsMonday,
            onChanged: (v) => _set(context, ref, (x) => x.copyWith(weekStartsMonday: v)),
          ),
          const ListTile(title: Text('貨幣單位'), trailing: Text('TWD'), subtitle: Text('目前只支援新台幣')),
        ]),
      ),
      const SectionTitle('PT 設定'),
      Card(
        child: Column(children: [
          ListTile(
            title: const Text('每月自動 PT 上限'),
            subtitle: const Text('收入、省下金額、月結算加起來的上限。財務目標不受限。0 = 不設上限'),
            trailing: Text(r.monthlyCapDeci == 0 ? '不限' : '${formatPt(r.monthlyCapDeci)} PT'),
            onTap: () async {
              final v = await promptText(context,
                  title: '每月 PT 上限', label: 'PT（0 = 不設上限）', initial: (r.monthlyCapDeci ~/ 10).toString(), numeric: true);
              final n = parseIntOrNull(v);
              if (n == null || !context.mounted) return;
              await _set(context, ref, (x) => x.copyWith(ptRates: x.ptRates.copyWith(monthlyCapDeci: n * 10)));
            },
          ),
          ExpansionTile(
            title: const Text('PT 換算比率（進階）'),
            children: [
              ListTile(
                title: const Text('類別層省錢'),
                trailing: Text('× ${r.categorySaving}'),
                onTap: () => _rate(context, ref, title: '類別層省錢', current: r.categorySaving, apply: (p, v) => p.copyWith(categorySaving: v)),
              ),
              ListTile(
                title: const Text('總額層省錢'),
                trailing: Text('× ${r.totalSaving}'),
                onTap: () => _rate(context, ref, title: '總額層省錢', current: r.totalSaving, apply: (p, v) => p.copyWith(totalSaving: v)),
              ),
              ListTile(
                title: const Text('收入記帳'),
                trailing: Text('× ${r.income}'),
                onTap: () => _rate(context, ref, title: '收入記帳', current: r.income, apply: (p, v) => p.copyWith(income: v)),
              ),
              ListTile(
                title: const Text('消費省下金額'),
                trailing: Text('× ${r.savedAmount}'),
                onTap: () => _rate(context, ref, title: '消費省下金額', current: r.savedAmount, apply: (p, v) => p.copyWith(savedAmount: v)),
              ),
              ListTile(
                title: const Text('恢復預設比率'),
                leading: const Icon(Icons.restore),
                onTap: () => _set(context, ref, (x) => x.copyWith(ptRates: PtRates(monthlyCapDeci: x.ptRates.monthlyCapDeci))),
              ),
            ],
          ),
        ]),
      ),
      const SectionTitle('寵物設定'),
      Card(
        child: Column(children: [
          SwitchListTile(
            title: const Text('輕鬆模式'),
            subtitle: const Text('屬性下降速度減半'),
            value: s.easyMode,
            onChanged: (v) => _set(context, ref, (x) => x.copyWith(easyMode: v)),
          ),
          SwitchListTile(
            title: const Text('關閉 San 值亂碼效果'),
            subtitle: const Text('無障礙選項：寵物失控時文字不會變亂碼、畫面不會變灰'),
            value: s.disableGarble,
            onChanged: (v) => _set(context, ref, (x) => x.copyWith(disableGarble: v)),
          ),
          SwitchListTile(
            title: const Text('關閉 San check'),
            subtitle: const Text('無障礙選項：衝動消費、深夜記帳等不會扣理智值'),
            value: s.disableSanCheck,
            onChanged: (v) => _set(context, ref, (x) => x.copyWith(disableSanCheck: v)),
          ),
          ListTile(
            title: const Text('衝動消費門檻'),
            subtitle: const Text('單筆支出超過這個金額會觸發 San check'),
            trailing: Text('\$${s.impulseThreshold}'),
            onTap: () => _int(context, ref,
                title: '衝動消費門檻', label: '金額', current: s.impulseThreshold, min: 1, apply: (x, v) => x.copyWith(impulseThreshold: v)),
          ),
          ListTile(
            title: const Text('同類別每日筆數門檻'),
            subtitle: const Text('同一類別當天超過幾筆會觸發 San check'),
            trailing: Text('${s.repeatCategoryThreshold} 筆'),
            onTap: () => _int(context, ref,
                title: '同類別每日筆數', current: s.repeatCategoryThreshold, min: 1, max: 50,
                apply: (x, v) => x.copyWith(repeatCategoryThreshold: v)),
          ),
        ]),
      ),
      const SectionTitle('通知設定'),
      Card(
        child: Column(children: [
          SwitchListTile(
            title: const Text('手機通知'),
            subtitle: const Text('帳單、每日記帳、資產更新提醒'),
            value: s.notificationsEnabled,
            onChanged: (v) async {
              if (v) await ref.read(notificationSchedulerProvider).requestPermission();
              if (!context.mounted) return;
              await _set(context, ref, (x) => x.copyWith(notificationsEnabled: v));
              await ref.read(notificationServiceProvider).reschedule();
            },
          ),
          SwitchListTile(
            title: const Text('每日記帳提醒'),
            subtitle: const Text('今天已經記過帳就不會提醒'),
            value: s.dailyReminderEnabled,
            onChanged: s.notificationsEnabled
                ? (v) async {
                    await _set(context, ref, (x) => x.copyWith(dailyReminderEnabled: v));
                    await ref.read(notificationServiceProvider).reschedule();
                  }
                : null,
          ),
          ListTile(
            title: const Text('每日提醒時間'),
            trailing: Text(s.dailyReminderTime),
            onTap: () async {
              final parts = s.dailyReminderTime.split(':');
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
              );
              if (t == null || !context.mounted) return;
              final str = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              await _set(context, ref, (x) => x.copyWith(dailyReminderTime: str));
              await ref.read(notificationServiceProvider).reschedule();
            },
          ),
          ListTile(
            title: const Text('帳單預設提前幾天通知'),
            trailing: Text('${s.billRemindDaysDefault} 天'),
            onTap: () => _int(context, ref,
                title: '帳單提前幾天通知', current: s.billRemindDaysDefault, max: 30,
                apply: (x, v) => x.copyWith(billRemindDaysDefault: v)),
          ),
          SwitchListTile(
            title: const Text('接收全體推播'),
            subtitle: const Text('新功能公告、活動通知'),
            value: s.receiveBroadcast,
            onChanged: (v) => _set(context, ref, (x) => x.copyWith(receiveBroadcast: v)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('重新排程通知'),
            subtitle: const Text('改了帳單或時間後會自動排程，通常不需要按'),
            onTap: () async {
              final n = await ref.read(notificationServiceProvider).reschedule();
              if (context.mounted) toast(context, n < 0 ? '排程失敗，請確認通知權限' : '已排程 $n 則通知');
            },
          ),
        ]),
      ),
      const SectionTitle('資料設定'),
      Card(
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('資料加密儲存在本機'),
            subtitle: Text('使用 SQLCipher 加密，不會上傳到任何伺服器'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('匯出備份'),
            subtitle: const Text('完整備份（JSON）＋記帳明細（CSV，可用 Excel 開）。可存到 Google Drive'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('從備份還原'),
            subtitle: const Text('選擇之前匯出的 JSON 檔，會覆蓋目前所有資料'),
            onTap: () => _import(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_sync_outlined),
            title: Text('Google Drive 自動備份'),
            subtitle: Text('v1.2 推出'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('清除所有資料', style: TextStyle(color: Colors.red)),
            subtitle: const Text('寵物、記帳、道具、設定全部刪除，無法復原'),
            onTap: () => _clearAll(context, ref),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(servicesProvider);
    final b = BackupService(svc.ctx);
    final stamp = dateKey(svc.ctx.now());
    try {
      await shareTextFiles({
        'money_pet_backup_$stamp.json': await b.exportJson(),
        'money_pet_transactions_$stamp.csv': await b.exportTransactionsCsv(),
      }, text: '錢寵備份 $stamp');
    } catch (e) {
      if (context.mounted) toast(context, '匯出失敗：$e');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: '從備份還原？',
        message: '目前手機上的所有資料都會被備份檔的內容取代。建議先匯出一份目前的備份。',
        confirm: '選擇檔案',
        danger: true);
    if (!ok || !context.mounted) return;
    final String? text;
    try {
      text = await pickTextFile();
    } catch (e) {
      if (context.mounted) toast(context, '無法讀取檔案：$e');
      return;
    }
    if (text == null || !context.mounted) return;
    final r = await runAction(context, ref, (s) => BackupService(s.ctx).importJson(text!));
    if (r != null && context.mounted) {
      toast(context, '還原完成（${r.rows} 筆資料）');
      await ref.read(notificationServiceProvider).reschedule();
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final first = await confirmDialog(context,
        title: '清除所有資料？', message: '所有資料都會被刪除，而且無法復原。', confirm: '繼續', danger: true);
    if (!first || !context.mounted) return;
    final typed = await promptText(context, title: '再確認一次', label: '請輸入「刪除」兩個字');
    if (typed?.trim() != '刪除' || !context.mounted) return;
    await runAction(context, ref, (svc) => svc.clearAllData());
    await ref.read(notificationServiceProvider).reschedule(); // 資料清空 → 取消所有通知
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}
