import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/enums.dart';
import '../../domain/finance_rules.dart';
import '../../services/report_service.dart';
import '../../state/providers.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

final _netWorthHistoryProvider = FutureProvider<List<(DateTime, int)>>((ref) {
  ref.watch(dataVersionProvider);
  return ReportService(ref.watch(servicesProvider).ctx).netWorthHistory();
});

class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(servicesProvider).ctx.now();
    return Scaffold(
      appBar: AppBar(title: const Text('資產統計')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAccount(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增帳戶'),
      ),
      body: AsyncView(ref.watch(assetsProvider), builder: (accounts) {
        final total = accounts.fold<double>(0, (s, a) => s + a.total);
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('總資產', style: Theme.of(context).textTheme.labelLarge),
                Text(formatMoney(total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                Builder(builder: (_) {
                  final h = ref.watch(_netWorthHistoryProvider).value ?? const [];
                  if (h.length < 2) return const SizedBox.shrink();
                  final diff = h.last.$2 - h.first.$2;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 12),
                    LineChart(
                      values: [for (final e in h) e.$2.toDouble()],
                      color: diff >= 0 ? Colors.green : Colors.red,
                      height: 90,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '近 90 天 ${diff >= 0 ? '+' : ''}${formatMoney(diff)}'
                      '（${DateFormat('M/d').format(h.first.$1)} 起）',
                      style: TextStyle(color: diff >= 0 ? Colors.green.shade700 : Colors.red, fontSize: 12),
                    ),
                  ]);
                }),
                const SizedBox(height: 4),
                const Text('每 3 天更新一次餘額可以完成固定任務。股價為手動輸入。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
          if (accounts.isEmpty)
            const EmptyHint('新增銀行、證券、現金等帳戶，掌握自己的總資產', icon: Icons.account_balance),
          for (final type in AssetType.values)
            if (accounts.any((a) => a.type == type)) ...[
              SectionTitle(type.label),
              for (final a in accounts.where((a) => a.type == type))
                _AccountCard(account: a, stale: isAssetStale(a.lastUpdated, now)),
            ],
        ]);
      }),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final balance = TextEditingController();
    var type = AssetType.bank;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('新增帳戶'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<AssetType>(
              segments: [for (final t in AssetType.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {type},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => type = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: '名稱', hintText: '台新銀行')),
            const SizedBox(height: 12),
            TextField(
              controller: balance,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: InputDecoration(
                labelText: type == AssetType.securities ? '交割戶現金' : '目前餘額',
                helperText: type == AssetType.securities ? '股票之後可在帳戶裡新增' : null,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(c, ref, (s) async {
                  await s.assets.addAccount(name.text, type, parseIntOrNull(balance.text) ?? 0);
                  return true;
                });
                if (ok == true && c.mounted) Navigator.pop(c);
              },
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, required this.stale});
  final AssetAccount account;
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
    final updated = a.lastUpdated == null ? '從未更新' : '更新於 ${DateFormat('M/d HH:mm').format(a.lastUpdated!)}';
    return Card(
      child: Column(children: [
        ListTile(
          title: Text(a.name),
          subtitle: Text(updated, style: TextStyle(color: stale ? Colors.orange.shade800 : null)),
          trailing: Text(formatMoney(a.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          onTap: () => _editBalance(context, ref),
          onLongPress: () => _menu(context, ref),
        ),
        if (a.type == AssetType.securities) ...[
          for (final st in a.stocks)
            ListTile(
              dense: true,
              leading: const Icon(Icons.show_chart),
              title: Text('${st.name}${st.code == null ? '' : '（${st.code}）'}'),
              subtitle: Text('${_fmtNum(st.quantity)} 股 × ${_fmtNum(st.price)}'),
              trailing: Text(formatMoney(st.marketValue)),
              onTap: () => _editStock(context, ref, st),
              onLongPress: () async {
                if (await confirmDialog(context, title: '刪除 ${st.name}？', confirm: '刪除', danger: true) &&
                    context.mounted) {
                  await runAction(context, ref, (s) => s.assets.deleteStock(st.id));
                }
              },
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.cases_outlined),
            title: Text('交割戶現金 ${formatMoney(a.balance)}'),
            trailing: TextButton.icon(
              onPressed: () => _editStock(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('股票'),
            ),
          ),
        ],
      ]),
    );
  }

  String _fmtNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> _editBalance(BuildContext context, WidgetRef ref) async {
    final v = await promptText(context,
        title: '更新「${account.name}」',
        label: account.type == AssetType.securities ? '交割戶現金' : '目前餘額',
        initial: account.balance.toString(),
        numeric: true);
    final n = parseIntOrNull(v);
    if (n == null || !context.mounted) return;
    await runAction(context, ref, (s) => s.assets.updateBalance(account.id, n), successMessage: '已更新');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('重新命名'), onTap: () => Navigator.pop(c, 'rename')),
          ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('刪除帳戶'),
              onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final n = await promptText(context, title: '重新命名', initial: account.name);
      if (n != null && context.mounted) {
        await runAction(context, ref, (s) => s.assets.renameAccount(account.id, n));
      }
    } else if (action == 'delete') {
      if (await confirmDialog(context, title: '刪除「${account.name}」？', message: '歷史紀錄也會一起刪除。', confirm: '刪除', danger: true) &&
          context.mounted) {
        await runAction(context, ref, (s) => s.assets.deleteAccount(account.id));
      }
    }
  }

  Future<void> _editStock(BuildContext context, WidgetRef ref, AssetStock? st) async {
    final name = TextEditingController(text: st?.name);
    final code = TextEditingController(text: st?.code);
    final qty = TextEditingController(text: st == null ? '' : _fmtNum(st.quantity));
    final price = TextEditingController(text: st == null ? '' : _fmtNum(st.price));
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(st == null ? '新增股票' : '更新 ${st.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: '股票名稱', hintText: '台積電')),
          const SizedBox(height: 8),
          TextField(controller: code, decoration: const InputDecoration(labelText: '代號（選填）', hintText: '2330')),
          const SizedBox(height: 8),
          TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: const InputDecoration(labelText: '持有股數')),
          const SizedBox(height: 8),
          TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: const InputDecoration(labelText: '目前股價')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final ok = await runAction(c, ref, (s) async {
                await s.assets.upsertStock(
                  id: st?.id,
                  accountId: account.id,
                  name: name.text,
                  code: code.text,
                  quantity: double.tryParse(qty.text) ?? 0,
                  price: double.tryParse(price.text) ?? 0,
                );
                return true;
              });
              if (ok == true && c.mounted) Navigator.pop(c);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}
