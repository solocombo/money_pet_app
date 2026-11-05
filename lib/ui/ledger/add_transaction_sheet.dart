import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/enums.dart';
import '../../domain/items.dart';
import '../../domain/pt_rules.dart';
import '../../domain/tasks.dart';
import '../../services/ledger_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// 開啟記帳表單。記帳成功後顯示結果（掉落道具、PT、San check）。
Future<RecordOutcome?> showAddTransaction(BuildContext context,
    {Category? initialCategory}) async {
  final outcome = await Navigator.of(context).push<RecordOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddTransactionPage(initialCategory: initialCategory),
    ),
  );
  if (outcome != null && context.mounted) {
    await showRecordOutcome(context, outcome);
  }
  return outcome;
}

/// 編輯既有交易（不會重新掉道具）。
Future<void> showEditTransaction(BuildContext context, Txn txn) async {
  final outcome = await Navigator.of(context).push<RecordOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddTransactionPage(editing: txn),
    ),
  );
  if (outcome == null || !context.mounted) return;
  final notes = <String>[
    if (outcome.ptAwardedDeci != txn.ptAwardedDeci)
      'PT ${formatPt(txn.ptAwardedDeci)} → ${formatPt(outcome.ptAwardedDeci)}',
    if (outcome.newCondition != null) '類別超支，寵物得了「${outcome.newCondition!.label}」',
  ];
  toast(context, notes.isEmpty ? '已更新' : '已更新：${notes.join('、')}');
}

class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({super.key, this.initialCategory, this.editing});
  final Category? initialCategory;
  final Txn? editing;

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  var _type = TransactionType.expense;
  late Category _category = widget.initialCategory ?? Category.dining;
  var _income = IncomeCategory.salary;
  final _amount = TextEditingController();
  final _saved = TextEditingController();
  final _note = TextEditingController();
  String? _paymentId;
  DateTime? _date; // null = 現在
  var _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      if (e.category != null) _category = e.category!;
      if (e.incomeCategory != null) _income = e.incomeCategory!;
      _amount.text = e.amount.toString();
      if (e.savedAmount > 0) _saved.text = e.savedAmount.toString();
      _note.text = e.note ?? '';
      _paymentId = e.paymentMethodId;
      _date = e.occurredAt;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _saved.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isExpense => _type == TransactionType.expense;

  Future<void> _submit() async {
    final amount = parseIntOrNull(_amount.text) ?? 0;
    final saved = parseIntOrNull(_saved.text) ?? 0;
    if (amount <= 0) {
      _snack('請輸入金額');
      return;
    }
    final err = _isExpense ? validateSavedAmount(amount: amount, saved: saved) : null;
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _saving = true);
    DateTime? at;
    final editing = widget.editing;
    if (editing != null && _date != null && DateUtils.isSameDay(_date, editing.occurredAt)) {
      at = editing.occurredAt; // 沒改日期就保留原本時間
    } else if (_date != null) {
      final now = DateTime.now();
      // 補記過去日期時，時間用中午，避免被誤判為深夜記帳。
      at = DateUtils.isSameDay(_date, now)
          ? now
          : DateTime(_date!.year, _date!.month, _date!.day, 12);
    }
    final outcome = await runAction(context, ref, (s) {
      if (editing != null) {
        return s.ledger.updateTransaction(
          editing.id,
          categoryName: _isExpense ? _category.name : _income.name,
          amount: amount,
          savedAmount: _isExpense ? saved : 0,
          paymentMethodId: _paymentId,
          note: _note.text,
          occurredAt: at ?? DateTime.now(),
        );
      }
      return _isExpense
          ? s.ledger.addExpense(
              category: _category,
              amount: amount,
              savedAmount: saved,
              paymentMethodId: _paymentId,
              note: _note.text,
              occurredAt: at,
            )
          : s.ledger.addIncome(
              category: _income,
              amount: amount,
              paymentMethodId: _paymentId,
              note: _note.text,
              occurredAt: at,
            );
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (outcome != null) Navigator.pop(context, outcome);
  }

  void _snack(String m) =>
      toast(context, m);

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(paymentMethodsProvider).value ?? const [];
    final dateLabel = _date == null ? '今天' : DateFormat('M/d (E)', 'zh_TW').format(_date!);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '編輯紀錄' : '記一筆'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: const Text('儲存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isEdit) SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(value: TransactionType.expense, label: Text('支出'), icon: Icon(Icons.remove)),
              ButtonSegment(value: TransactionType.income, label: Text('收入'), icon: Icon(Icons.add)),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: !_isEdit,
            keyboardType: TextInputType.number,
            inputFormatters: digitsOnly,
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: const InputDecoration(labelText: '金額', prefixText: '\$ '),
          ),
          const SizedBox(height: 16),
          Text('類別', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_isExpense) _expenseCategories() else _incomeCategories(),
          const SizedBox(height: 16),
          if (_isExpense) ...[
            TextField(
              controller: _saved,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              decoration: const InputDecoration(
                labelText: '本次省下金額（選填）',
                helperText: '信用卡回饋、折扣、點數折抵等，不能超過消費金額',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<String?>(
            initialValue: _paymentId,
            decoration: const InputDecoration(labelText: '支付工具'),
            items: [
              const DropdownMenuItem(value: null, child: Text('未指定')),
              for (final m in methods)
                DropdownMenuItem(value: m.id, child: Text('${m.name}（${m.type.label}）')),
            ],
            onChanged: (v) => setState(() => _paymentId = v),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text('日期：$dateLabel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _date ?? now,
                // 編輯很舊的紀錄時，最早日期要能涵蓋它，不然 date picker 會 assert 失敗
                firstDate: _date != null && _date!.isBefore(DateTime(now.year - 1))
                    ? DateTime(_date!.year, _date!.month, _date!.day)
                    : DateTime(now.year - 1),
                lastDate: now,
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: '備註（選填）'),
            maxLength: 100,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.check),
            label: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  Widget _expenseCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in CategoryGroup.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              g.attribute == null ? g.label : '${g.label} · ${g.attribute!.label}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in Category.values.where((c) => c.group == g))
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _incomeCategories() => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final c in IncomeCategory.values)
            ChoiceChip(
              label: Text('${c.emoji} ${c.label}'),
              selected: _income == c,
              onSelected: (_) => setState(() => _income = c),
            ),
        ],
      );
}

/// 記帳結果：道具掉落動畫 + PT + San check + 生病。
Future<void> showRecordOutcome(BuildContext context, RecordOutcome o) {
  final lines = <Widget>[];
  void line(String emoji, String text, {Color? color}) => lines.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
      ));

  if (o.ptAwardedDeci > 0) {
    line('⭐', '獲得 ${formatPt(o.ptAwardedDeci)} PT');
  }
  if (o.ptCapped) {
    line('🚧', '本月自動 PT 已達上限，'
        '${o.ptAwardedDeci > 0 ? '只拿到部分' : '這筆沒有 PT'}');
  }
  final hasPtSource = !o.txn.isExpense || o.txn.savedAmount > 0;
  if (o.noBudget && hasPtSource) {
    line('💡', '本月還沒設定預算，所以不會獲得 PT（道具照拿）。可以在「預算」設定。');
  }
  if (o.pastMonth && hasPtSource && !o.noBudget) {
    line('📅', '補記過去月份的帳不會獲得 PT。');
  }
  if (o.dropLimitReached) {
    line('🎒', '今天的道具掉落次數已用完，明天再來！');
  }
  if (o.cancelledNoSpend) {
    line('↩️', '今天有支出了，已取消「本日無支出」打卡（收回 $noSpendCoinReward 金幣）。');
  }
  if (o.sanTriggers.isNotEmpty) {
    final why = o.sanTriggers.map((t) => t.label).join('、');
    if (o.sanCheckFailed) {
      line('🌀', 'San check 失敗（$why）：理智 -10', color: Colors.deepPurple);
    } else {
      line('🧘', 'San check 通過（$why）');
    }
  }
  if (o.becameInsane) {
    line('👁️', '寵物失去理智了……連續記帳 3 天可以讓牠恢復。', color: Colors.deepPurple);
  }
  if (o.newCondition != null) {
    line('🤒', '類別超支，寵物得了「${o.newCondition!.label}」：${o.newCondition!.effect}',
        color: Colors.red);
  }

  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('記帳完成！'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (o.droppedItem != null) _DropWithReroll(txnId: o.txn.id, item: o.droppedItem!),
            ...lines,
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('好'))],
    ),
  );
}

/// 掉落道具 +「看廣告重抽」（每天 2 次）。
class _DropWithReroll extends ConsumerStatefulWidget {
  const _DropWithReroll({required this.txnId, required this.item});
  final String txnId;
  final ItemDef item;
  @override
  ConsumerState<_DropWithReroll> createState() => _DropWithRerollState();
}

class _DropWithRerollState extends ConsumerState<_DropWithReroll> {
  late ItemDef _item = widget.item;
  var _canReroll = false;
  var _busy = false;
  var _round = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await ref.read(servicesProvider).ads.canReroll(widget.txnId);
    if (mounted) setState(() => _canReroll = ok);
  }

  Future<void> _reroll() async {
    setState(() => _busy = true);
    final watched = await watchRewardedAd(ref);
    if (!mounted) return;
    if (!watched) {
      setState(() => _busy = false);
      toast(context, '廣告沒有看完或暫時無法載入');
      return;
    }
    final next = await runAction(context, ref, (s) => s.ads.reroll(widget.txnId));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (next != null) {
        _item = next;
        _round++;
      }
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _ItemDrop(key: ValueKey(_round), item: _item),
        if (_canReroll)
          TextButton.icon(
            onPressed: _busy ? null : _reroll,
            icon: const Text('🎲'),
            label: Text(ref.watch(premiumProvider).value == true ? '不喜歡？重抽一次' : '不喜歡？看廣告重抽'),
          ),
      ]);
}

class _ItemDrop extends StatelessWidget {
  const _ItemDrop({super.key, required this.item});
  final ItemDef item;

  @override
  Widget build(BuildContext context) {
    final color = rarityColor(item.rarity);
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.2, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
            color: color.withValues(alpha: 0.08),
          ),
          child: Column(children: [
            Text(item.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 4),
            Text('獲得 ${item.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${item.rarity.label} · ${item.effectText}',
                style: TextStyle(color: color)),
          ]),
        ),
      ),
    );
  }
}
