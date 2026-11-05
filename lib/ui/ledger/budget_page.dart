import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/finance_rules.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key, required this.month});
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider(month));
    final settings = ref.watch(settingsProvider).value;
    final m = parseMonthKey(month);
    final threshold = ((settings?.overspendThreshold ?? 0.2) * 100).round();

    Future<void> edit(CategoryGroup? g, int? current) async {
      final v = await promptText(
        context,
        title: '${g?.label ?? '總'}預算',
        label: '金額（留空 = 不設定）',
        initial: current?.toString() ?? '',
        numeric: true,
      );
      if (v == null || !context.mounted) return;
      await runAction(context, ref, (s) => s.ledger.setBudget(month, g, parseIntOrNull(v)));
    }

    return Scaffold(
      appBar: AppBar(title: Text('${m.month} 月預算')),
      body: AsyncView(summary, builder: (s) {
        final b = s.budgets;
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '• 有設預算才會獲得 PT（收入、省下金額、月底結算）。\n'
              '• 月底結算：每個類別省下的錢 × 0.1、總額省下的錢再 × 0.1，兩層都省到就是雙重獎勵。\n'
              '• 💥 預算暴擊：總額省下兩成以上、而且沒有類別超支，結算 PT 加倍！\n'
              '• 單一類別超支 $threshold% 以上，寵物會生病；超過半數類別超支，當月結算拿不到 PT。\n'
              '• 下個月沒設定時，會自動沿用這個月的預算。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Text('💰', style: TextStyle(fontSize: 24)),
              title: const Text('總預算'),
              subtitle: Text('已花 ${formatMoney(s.expense)}'),
              trailing: Text(b.total == null ? '未設定' : formatMoney(b.total!),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => edit(null, b.total),
            ),
          ),
          const SectionTitle('類別預算'),
          Card(
            child: Column(children: [
              for (final g in CategoryGroup.values)
                ListTile(
                  title: Text(g.label),
                  subtitle: Text('已花 ${formatMoney(s.byGroup[g] ?? 0)}'
                      ' · 超支會得「${g.condition.label}」'),
                  trailing: Text(b.groups[g] == null ? '未設定' : formatMoney(b.groups[g]!)),
                  onTap: () => edit(g, b.groups[g]),
                ),
            ]),
          ),
          const SizedBox(height: 32),
        ]);
      }),
    );
  }
}
