import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/finance_rules.dart';
import '../../services/report_service.dart';
import '../../state/providers.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

final monthReportProvider = FutureProvider.family<MonthReport, String>((ref, month) {
  ref.watch(dataVersionProvider);
  return ReportService(ref.watch(servicesProvider).ctx).monthReport(month);
});

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.month});
  final String month;
  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  late String _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentMonthProvider);
    final m = parseMonthKey(_month);
    return Scaffold(
      appBar: AppBar(title: const Text('月報表')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _month = previousMonthKey(_month)),
          ),
          Text('${m.year} 年 ${m.month} 月', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _month == current ? null : () => setState(() => _month = nextMonthKey(_month)),
          ),
        ]),
        AsyncView(ref.watch(monthReportProvider(_month)), builder: (r) => _Body(r: r)),
      ]),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.r});
  final MonthReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = r.changeVsPrev;
    final segments = [
      for (final g in CategoryGroup.values)
        if ((r.byGroup[g] ?? 0) > 0)
          ChartSegment(g.label, r.byGroup[g]!.toDouble(), groupPalette[g.index]),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ---- 總覽 ----
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本月支出', style: theme.textTheme.labelLarge),
            Text(formatMoney(r.expense),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (change != null)
              Text(
                change == 0
                    ? '和上個月一樣'
                    : '比上個月${change > 0 ? '多' : '少'} ${(change.abs() * 100).round()}%'
                        '（${formatMoney(r.prevExpense)}）',
                style: TextStyle(color: change > 0 ? Colors.red : Colors.green.shade700),
              ),
            const Divider(height: 24),
            Wrap(spacing: 24, runSpacing: 8, children: [
              _Stat('收入', formatMoney(r.income)),
              _Stat('結餘', formatMoney(r.income - r.expense)),
              _Stat('日平均', formatMoney(r.dailyAverage)),
              _Stat('省下', formatMoney(r.saved)),
              _Stat('記帳天數', '${r.recordedDays} / ${r.daysElapsed}'),
              _Stat('無支出', '${r.noSpendDays} 天'),
            ]),
          ]),
        ),
      ),

      // ---- 類別 ----
      const SectionTitle('支出分布'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: segments.isEmpty
              ? const EmptyHint('這個月沒有支出', icon: Icons.pie_chart_outline)
              : Row(children: [
                  DonutChart(
                    segments: segments,
                    size: 140,
                    center: Text(formatMoney(r.expense), style: theme.textTheme.labelLarge),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final s in segments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(s.label)),
                            Text('${(s.value / r.expense * 100).round()}%', style: theme.textTheme.bodySmall),
                          ]),
                        ),
                    ]),
                  ),
                ]),
        ),
      ),
      if (r.topCategories.isNotEmpty)
        Card(
          child: Column(children: [
            for (final c in r.topCategories)
              ListTile(
                dense: true,
                leading: Text(c.category.emoji, style: const TextStyle(fontSize: 20)),
                title: Text(c.category.label),
                subtitle: Text('${c.count} 筆'),
                trailing: Text(formatMoney(c.amount)),
              ),
          ]),
        ),
      if (r.biggest != null)
        Card(
          child: ListTile(
            leading: const Text('💸', style: TextStyle(fontSize: 24)),
            title: const Text('本月最大一筆'),
            subtitle: Text('${r.biggest!.$1.label}${r.biggest!.$3 == null ? '' : '・${r.biggest!.$3}'}'),
            trailing: Text(formatMoney(r.biggest!.$2), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),

      // ---- 趨勢 ----
      const SectionTitle('近 6 個月'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            PairedBarChart(
              labels: [for (final t in r.trend) '${parseMonthKey(t.month).month}月'],
              a: [for (final t in r.trend) t.expense.toDouble()],
              b: [for (final t in r.trend) t.income.toDouble()],
              colorA: Colors.redAccent,
              colorB: Colors.green,
            ),
            const SizedBox(height: 8),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Legend(Colors.redAccent, '支出'),
              SizedBox(width: 16),
              _Legend(Colors.green, '收入'),
            ]),
          ]),
        ),
      ),

      // ---- 支付工具（信用卡檢討）----
      if (r.byPayment.isNotEmpty) ...[
        const SectionTitle('支付工具'),
        Card(
          child: Column(children: [
            for (final p in r.byPayment)
              ListTile(
                dense: true,
                leading: Icon(p.isCreditCard ? Icons.credit_card : Icons.payments_outlined),
                title: Text(p.name ?? '未指定'),
                trailing: Text(formatMoney(p.amount)),
              ),
            if (r.byPayment.any((p) => p.isCreditCard))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '💳 信用卡本月刷了 ${formatMoney(r.byPayment.where((p) => p.isCreditCard).fold<int>(0, (s, p) => s + p.amount))}，'
                  '想想看哪些是真的需要的？',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]);
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]);
}
