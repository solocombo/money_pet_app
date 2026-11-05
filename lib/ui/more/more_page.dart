import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/finance_rules.dart';
import '../../state/providers.dart';
import '../ledger/budget_page.dart';
import '../widgets/common.dart';
import 'assets_page.dart';
import 'bills_page.dart';
import 'settings_page.dart';

/// 隱私權政策摘要（完整版見 docs/privacy.md，上架時以 GitHub Pages 公開）。
const String privacySummary = '''• 你的所有資料只存在這支手機裡，並以 SQLCipher 加密。開發者沒有伺服器，也看不到你的資料。

• 提醒使用手機的本地通知，不經過任何伺服器。

• 「匯出備份」產生的檔案只會送到你自己選擇的地方。備份檔未加密，請妥善保管。

• 目前不使用任何分析、廣告或追蹤服務。未來加入 Google Drive 備份、推播公告或自願觀看的廣告時，會先更新本政策。

• 「設定 → 清除所有資料」或解除安裝 APP，即可永久刪除所有資料。''';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final accounts = ref.watch(assetsProvider).value ?? const [];
    final netWorth = accounts.fold<double>(0, (s, a) => s + a.total);
    final dueSoon = ref.watch(billsDueSoonProvider).value?.length ?? 0;

    void go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const GText('更多')),
      body: ListView(children: [
        const SectionTitle('財務工具'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('資產統計'),
              subtitle: Text(accounts.isEmpty ? '銀行、證券、現金' : '總資產 ${formatMoney(netWorth)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => go(const AssetsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('帳單提醒'),
              subtitle: Text(dueSoon > 0 ? '$dueSoon 筆即將到期' : '信用卡、水電、房租、訂閱'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => go(const BillsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('預算'),
              subtitle: const Text('設定預算才能獲得 PT'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => go(BudgetPage(month: month)),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: const Text('支付工具'),
              subtitle: const Text('現金、信用卡、轉帳'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => go(const PaymentMethodsPage()),
            ),
          ]),
        ),
        const SectionTitle('其他'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => go(const SettingsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.pets),
              title: const Text('幫寵物改名'),
              onTap: () async {
                final pet = ref.read(petProvider).value;
                final n = await promptText(context, title: '幫寵物改名', initial: pet?.name ?? '');
                if (n != null && context.mounted) {
                  await runAction(context, ref, (s) => s.pets.rename(n));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隱私權政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('隱私權政策'),
                  content: const SingleChildScrollView(child: Text(privacySummary)),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('關閉'))],
                ),
              ),
            ),
            const AboutListTile(
              icon: Icon(Icons.info_outline),
              applicationName: '錢寵',
              applicationVersion: '0.1.0 (MVP)',
              applicationLegalese: '記帳養寵物，省錢換獎勵。\n所有資料只存在你的手機裡。',
            ),
          ]),
        ),
      ]),
    );
  }
}
