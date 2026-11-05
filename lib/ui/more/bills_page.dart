import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/enums.dart';
import '../../domain/finance_rules.dart';
import '../../state/providers.dart';
import '../ledger/add_transaction_sheet.dart' show showRecordOutcome;
import '../widgets/common.dart';

class BillsPage extends ConsumerWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(servicesProvider).ctx.now();
    final today = DateTime(now.year, now.month, now.day);
    return Scaffold(
      appBar: AppBar(title: const Text('帳單提醒')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBillEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('新增帳單'),
      ),
      body: AsyncView(ref.watch(billsUpcomingProvider), builder: (dues) {
        final all = ref.watch(_allBillsProvider).value ?? const <Bill>[];
        final inactive = all.where((b) => !b.isActive).toList();
        if (dues.isEmpty && inactive.isEmpty) {
          return const EmptyHint('新增信用卡、水電、房租、訂閱等帳單，到期前會提醒你', icon: Icons.receipt_long);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          const SectionTitle('即將到期'),
          for (final d in dues) _BillTile(due: d, today: today),
          if (inactive.isNotEmpty) ...[
            const SectionTitle('已暫停'),
            for (final b in inactive)
              Card(
                child: ListTile(
                  title: Text(b.name),
                  subtitle: Text('每月 ${b.dueDay} 號 · ${b.recurrence.label}'),
                  trailing: const Icon(Icons.pause_circle_outline),
                  onTap: () => showBillEditor(context, ref, b),
                ),
              ),
          ],
        ]);
      }),
    );
  }
}

final _allBillsProvider = FutureProvider<List<Bill>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(servicesProvider).bills.bills();
});

class _BillTile extends ConsumerWidget {
  const _BillTile({required this.due, required this.today});
  final BillDue due;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = due.bill;
    final days = due.dueDate.difference(today).inDays;
    final soon = days <= b.remindDaysBefore;
    final when = days < 0 ? '逾期 ${-days} 天' : (days == 0 ? '今天' : '$days 天後');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: days < 0 ? Colors.red : (soon ? Colors.orange : Colors.grey.shade300),
          child: Text('${due.dueDate.day}', style: TextStyle(color: soon || days < 0 ? Colors.white : null)),
        ),
        title: Text(b.name),
        subtitle: Text('${DateFormat('M/d').format(due.dueDate)}（$when）· ${b.type.label} · ${b.recurrence.label}'),
        trailing: due.isPaid
            ? const Chip(label: Text('已繳'))
            : FilledButton.tonal(onPressed: () => _pay(context, ref), child: const Text('繳費')),
        onTap: () => showBillEditor(context, ref, b),
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final amountCtl = TextEditingController(text: due.bill.amount?.toString() ?? '');
    var record = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('繳「${due.bill.name}」'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amountCtl,
              autofocus: due.bill.amount == null,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: const InputDecoration(labelText: '實際金額', prefixText: '\$ '),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: record,
              onChanged: (v) => setState(() => record = v ?? true),
              title: Text('一鍵記帳（${due.bill.category.label}）'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('已繳')),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    final amount = parseIntOrNull(amountCtl.text) ?? 0;
    final result = await runAction(context, ref, (s) async =>
        (await s.bills.markPaid(due, amount: amount, recordTransaction: record),));
    final outcome = result?.$1;
    if (outcome != null && context.mounted) await showRecordOutcome(context, outcome);
  }
}

Future<void> showBillEditor(BuildContext context, WidgetRef ref, Bill? bill) async {
  final name = TextEditingController(text: bill?.name);
  final amount = TextEditingController(text: bill?.amount?.toString());
  final dueDay = TextEditingController(text: (bill?.dueDay ?? 10).toString());
  final settings = ref.read(settingsProvider).value;
  final remind = TextEditingController(
      text: (bill?.remindDaysBefore ?? settings?.billRemindDaysDefault ?? 3).toString());
  var type = bill?.type ?? BillType.subscription;
  var recurrence = bill?.recurrence ?? Recurrence.monthly;
  var category = bill?.category ?? Category.subscription;
  var paymentId = bill?.paymentMethodId;
  var active = bill?.isActive ?? true;
  final methods = ref.read(paymentMethodsProvider).value ?? const <PaymentMethod>[];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(bill == null ? '新增帳單' : '編輯帳單', style: Theme.of(c).textTheme.titleLarge)),
              if (bill != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirmDialog(c, title: '刪除「${bill.name}」？', confirm: '刪除', danger: true) && c.mounted) {
                      await runAction(c, ref, (s) => s.bills.deleteBill(bill.id));
                      if (c.mounted) Navigator.pop(c);
                    }
                  },
                ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: '帳單名稱', hintText: 'Netflix、電費')),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final t in BillType.values)
                ChoiceChip(label: Text(t.label), selected: type == t, onSelected: (_) => setState(() => type = t)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: const InputDecoration(labelText: '金額（留空 = 每次手動輸入）', prefixText: '\$ '),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: dueDay,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsOnly,
                  decoration: const InputDecoration(labelText: '每月幾號到期'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: remind,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsOnly,
                  decoration: const InputDecoration(labelText: '提前幾天提醒'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<Recurrence>(
              segments: [for (final r in Recurrence.values) ButtonSegment(value: r, label: Text(r.label))],
              selected: {recurrence},
              onSelectionChanged: (v) => setState(() => recurrence = v.first),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Category>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '記帳類別'),
              items: [for (final cat in Category.values) DropdownMenuItem(value: cat, child: Text('${cat.emoji} ${cat.label}'))],
              onChanged: (v) => setState(() => category = v ?? category),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: methods.any((m) => m.id == paymentId) ? paymentId : null,
              decoration: const InputDecoration(labelText: '支付工具（選填）'),
              items: [
                const DropdownMenuItem(value: null, child: Text('未指定')),
                for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => setState(() => paymentId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('啟用提醒'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
            if (recurrence != Recurrence.monthly && bill == null)
              Text('${recurrence.label}帳單從本月開始起算。', style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(c, ref, (s) async {
                  await s.bills.saveBill(
                    id: bill?.id,
                    name: name.text,
                    type: type,
                    amount: parseIntOrNull(amount.text),
                    dueDay: parseIntOrNull(dueDay.text) ?? 0,
                    remindDaysBefore: parseIntOrNull(remind.text) ?? 3,
                    recurrence: recurrence,
                    category: category,
                    paymentMethodId: paymentId,
                    isActive: active,
                  );
                  return true;
                });
                if (ok == true && c.mounted) Navigator.pop(c);
              },
              child: const Text('儲存'),
            ),
          ]),
        ),
      );
    }),
  );
}

/// 支付工具管理。
class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('支付工具')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: AsyncView(ref.watch(paymentUsageProvider), builder: (list) {
        if (list.isEmpty) {
          return const EmptyHint('新增現金、信用卡、轉帳帳戶，記帳時就能選擇', icon: Icons.credit_card);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          for (final u in list)
            Card(
              child: ListTile(
                leading: Icon(switch (u.method.type) {
                  PaymentType.cash => Icons.payments_outlined,
                  PaymentType.creditCard => Icons.credit_card,
                  PaymentType.transfer => Icons.swap_horiz,
                  PaymentType.other => Icons.wallet,
                }),
                title: Text(u.method.name),
                subtitle: u.method.isCreditCard && u.method.creditLimit != null
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('本期 ${formatMoney(u.cycleSpent)} / 額度 ${formatMoney(u.method.creditLimit!)}'
                            '${u.method.billingDay != null ? ' · 帳單日 ${u.method.billingDay} 號' : ''}'
                            '${u.method.dueDay != null ? ' · 繳款日 ${u.method.dueDay} 號' : ''}'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (u.cycleSpent / u.method.creditLimit!).clamp(0, 1),
                          color: u.warning ? Colors.red : null,
                        ),
                        if (u.warning)
                          Text('已超過 ${((s?.creditWarnRatio ?? 0.8) * 100).round()}% 警戒線！',
                              style: const TextStyle(color: Colors.red)),
                      ])
                    : Text(u.method.type.label),
                onTap: () => _edit(context, ref, u.method),
              ),
            ),
        ]);
      }),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, PaymentMethod? m) async {
    final name = TextEditingController(text: m?.name);
    final limit = TextEditingController(text: m?.creditLimit?.toString());
    final billing = TextEditingController(text: m?.billingDay?.toString());
    final due = TextEditingController(text: m?.dueDay?.toString());
    var type = m?.type ?? PaymentType.creditCard;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(m == null ? '新增支付工具' : '編輯支付工具'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, children: [
                for (final t in PaymentType.values)
                  ChoiceChip(label: Text(t.label), selected: type == t, onSelected: (_) => setState(() => type = t)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: const InputDecoration(labelText: '名稱', hintText: '玉山 Pi 卡')),
              if (type == PaymentType.creditCard) ...[
                const SizedBox(height: 8),
                TextField(controller: limit, keyboardType: TextInputType.number, inputFormatters: digitsOnly,
                    decoration: const InputDecoration(labelText: '信用額度')),
                const SizedBox(height: 8),
                TextField(controller: billing, keyboardType: TextInputType.number, inputFormatters: digitsOnly,
                    decoration: const InputDecoration(labelText: '帳單日（每月幾號）')),
                const SizedBox(height: 8),
                TextField(controller: due, keyboardType: TextInputType.number, inputFormatters: digitsOnly,
                    decoration: const InputDecoration(labelText: '繳款日（每月幾號）')),
              ],
            ]),
          ),
          actions: [
            if (m != null)
              TextButton(
                onPressed: () async {
                  await runAction(c, ref, (s) => s.bills.archivePaymentMethod(m.id));
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('移除', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(c, ref, (s) async {
                  await s.bills.savePaymentMethod(
                    id: m?.id,
                    name: name.text,
                    type: type,
                    creditLimit: parseIntOrNull(limit.text),
                    billingDay: parseIntOrNull(billing.text),
                    dueDay: parseIntOrNull(due.text),
                  );
                  return true;
                });
                if (ok == true && c.mounted) Navigator.pop(c);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }
}
