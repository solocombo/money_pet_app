import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/finance_rules.dart';
import '../../domain/pt_rules.dart';
import '../../services/ledger_service.dart';
import '../../state/providers.dart';
import '../home/pet_page.dart' show TxnTile;
import '../widgets/common.dart';
import 'add_transaction_sheet.dart';
import 'budget_page.dart';

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});
  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  String? _month;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentMonthProvider);
    final month = _month ?? current;
    final summary = ref.watch(monthSummaryProvider(month));
    final txns = ref.watch(monthTxnProvider(month));
    final m = parseMonthKey(month);

    return Scaffold(
      appBar: AppBar(
        title: const GText('記帳'),
        actions: [
          IconButton(
            tooltip: '預算',
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => BudgetPage(month: current))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'ledger_add',
        onPressed: () => showAddTransaction(context),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = previousMonthKey(month)),
            ),
            Text('${m.year} 年 ${m.month} 月', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: month == current
                  ? null
                  : () => setState(() => _month = nextMonthKey(month)),
            ),
          ]),
          AsyncView(summary, builder: (s) => _SummaryCard(summary: s, isCurrent: month == current)),
          const SectionTitle('明細'),
          AsyncView(txns, builder: (list) {
            if (list.isEmpty) return const EmptyHint('這個月還沒有紀錄');
            return Card(
              child: Column(children: [
                for (final t in list)
                  Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) => _confirmDelete(t),
                    onDismissed: (_) =>
                        runAction(context, ref, (s) => s.ledger.deleteTransaction(t.id)),
                    child: TxnTile(
                      txn: t,
                      onTap: () => showEditTransaction(context, t),
                      onLongPress: () => _deleteViaDialog(t),
                    ),
                  ),
              ]),
            );
          }),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('點一下可以編輯，左滑或長按可以刪除。刪除會退回該筆獲得的 PT，若道具還在背包也會收回。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(Txn t) => confirmDialog(context,
      title: '刪除這筆紀錄？',
      message: '${t.categoryLabel} ${formatMoney(t.amount)}',
      confirm: '刪除',
      danger: true);

  Future<void> _deleteViaDialog(Txn t) async {
    if (await _confirmDelete(t) && mounted) {
      await runAction(context, ref, (s) => s.ledger.deleteTransaction(t.id));
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.isCurrent});
  final MonthSummary summary;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final b = s.budgets;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Figure('支出', formatMoney(s.expense)),
            _Figure('收入', formatMoney(s.income), color: Colors.green.shade700),
            _Figure('省下', formatMoney(s.saved)),
          ]),
          const Divider(height: 24),
          if (b.isEmpty)
            Text(
              isCurrent ? '💡 本月還沒設定預算：記帳只會拿到道具，不會獲得 PT。點右上角設定預算。' : '這個月沒有設定預算',
              style: TextStyle(color: theme.hintColor),
            )
          else ...[
            if (b.total != null) _BudgetBar(label: '總預算', budget: b.total!, spent: s.expense),
            for (final g in CategoryGroup.values)
              if (b.groups[g] != null)
                _BudgetBar(label: g.label, budget: b.groups[g]!, spent: s.byGroup[g] ?? 0),
          ],
          if (isCurrent && !b.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              s.ptCapDeci > 0
                  ? '本月自動 PT：${formatPt(s.ptEarnedDeci)} / ${formatPt(s.ptCapDeci)}（上限）'
                  : '本月自動 PT：${formatPt(s.ptEarnedDeci)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.label, required this.budget, required this.spent});
  final String label;
  final int budget;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final ratio = budget == 0 ? 0.0 : spent / budget;
    final color = ratio > 1 ? Colors.red : (ratio > 0.8 ? Colors.orange : Colors.green);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text('${formatMoney(spent)} / ${formatMoney(budget)}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ratio.clamp(0, 1),
          color: color,
          minHeight: 6,
          borderRadius: BorderRadius.circular(4),
        ),
      ]),
    );
  }
}
