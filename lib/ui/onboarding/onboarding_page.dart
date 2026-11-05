import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/pt_rules.dart';
import '../../domain/tasks.dart';
import '../../state/providers.dart';
import '../ledger/add_transaction_sheet.dart';
import '../tasks/tasks_page.dart' show showRewardEditor;
import '../widgets/common.dart';

/// Onboarding：歡迎 → 建立寵物 → 獎勵櫃（必填）→ 預算（可跳過）→ 第一筆帳（可跳過）→ 完成。
/// 原則：3 分鐘內完成，能跳過的都能跳過。中途關掉 APP，下次會從還沒做的步驟繼續。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int? _step;
  final _name = TextEditingController();
  var _type = PetType.cat;
  final _budget = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    final s = ref.read(servicesProvider);
    final pet = await s.pets.activePet();
    final rewards = await s.rewards.rewards();
    setState(() {
      _step = pet == null ? 0 : (rewards.isEmpty ? 2 : 3);
    });
  }

  void _next() => setState(() => _step = _step! + 1);

  Future<void> _finish() async {
    await runAction(context, ref, (s) => s.settings.update((x) => x.copyWith(onboardingDone: true)));
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = [_welcome, _createPet, _reward, _setBudget, _firstRecord, _done];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (step > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: LinearProgressIndicator(value: step / (pages.length - 1), borderRadius: BorderRadius.circular(4)),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey(step), child: pages[step]()),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _frame({
    required String emoji,
    required String title,
    required String body,
    Widget? content,
    required Widget primary,
    Widget? secondary,
  }) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      Center(child: Text(emoji, style: const TextStyle(fontSize: 72))),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(body, textAlign: TextAlign.center, style: t.bodyLarge),
      const SizedBox(height: 24),
      ?content,
      const SizedBox(height: 24),
      primary,
      if (secondary != null) ...[const SizedBox(height: 8), secondary],
    ]);
  }

  Widget _welcome() => _frame(
        emoji: '🐾',
        title: '歡迎來到錢寵',
        body: '記帳養寵物，省錢換獎勵。\n\n每記一筆帳，寵物就會得到道具；\n省下的錢會變成 PT，換你真正想要的獎勵。',
        primary: FilledButton(onPressed: _next, child: const Text('開始')),
      );

  Widget _createPet() => _frame(
        emoji: _type.emoji,
        title: '選一隻寵物',
        body: '每種寵物的理智值（San）不同：越高越不容易因為衝動消費而失控。',
        content: Column(children: [
          for (final t in PetType.values)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: _type == t ? Theme.of(context).colorScheme.primaryContainer : null,
              child: ListTile(
                leading: Text(t.emoji, style: const TextStyle(fontSize: 32)),
                title: Text(t.label),
                subtitle: Text('${t.description} · 理智 ${t.baseSan}'),
                trailing: _type == t ? const Icon(Icons.check_circle) : null,
                onTap: () => setState(() => _type = t),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textAlign: TextAlign.center,
            maxLength: 12,
            decoration: const InputDecoration(labelText: '幫牠取個名字'),
          ),
        ]),
        primary: FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final p = await runAction(context, ref,
                      (s) => s.pets.createPet(name: _name.text, type: _type));
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (p != null) {
                    toast(context, '${p.type.emoji} ${p.name} 開心地向你揮手！');
                    _next();
                  }
                },
          child: const Text('就決定是你了'),
        ),
      );

  Widget _reward() {
    final rewards = ref.watch(rewardsProvider).value ?? const [];
    return _frame(
      emoji: '🎁',
      title: '設定你的獎勵櫃',
      body: '省下來的錢會變成 PT。\n先想一個「存到 PT 就要犒賞自己」的現實獎勵！\n\n'
          '參考：小獎勵 500 PT、中獎勵 1500 PT、大獎勵 5000 PT',
      content: Column(children: [
        for (final r in rewards)
          ListTile(leading: const Text('🎁'), title: Text(r.name), trailing: Text('${formatPt(r.ptCostDeci)} PT')),
        OutlinedButton.icon(
          onPressed: () => showRewardEditor(context, ref),
          icon: const Icon(Icons.add),
          label: Text(rewards.isEmpty ? '新增獎勵' : '再加一個'),
        ),
      ]),
      primary: FilledButton(
        onPressed: rewards.isEmpty ? null : _next,
        child: Text(rewards.isEmpty ? '至少設定一個獎勵' : '下一步'),
      ),
    );
  }

  Widget _setBudget() => _frame(
        emoji: '📊',
        title: '設定本月預算',
        body: '有設預算才會獲得 PT：\n月底省下的錢 × 0.1 = PT。\n\n之後可以在「記帳 → 預算」細分到各類別。',
        content: TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: const InputDecoration(labelText: '本月總預算', prefixText: '\$ '),
        ),
        primary: FilledButton(
          onPressed: () async {
            final n = parseIntOrNull(_budget.text);
            if (n == null || n <= 0) {
              toast(context, '請輸入金額，或按「先跳過」');
              return;
            }
            final month = ref.read(currentMonthProvider);
            await runAction(context, ref, (s) => s.ledger.setBudget(month, null, n));
            if (mounted) _next();
          },
          child: const Text('設定'),
        ),
        secondary: TextButton(onPressed: _next, child: const Text('先跳過（之前不會獲得 PT）')),
      );

  Widget _firstRecord() => _frame(
        emoji: '✍️',
        title: '記下第一筆帳',
        body: '今天花了什麼錢？早餐、飲料、捷運都可以。\n記完就會看到道具掉落！',
        primary: FilledButton.icon(
          onPressed: () async {
            final o = await showAddTransaction(context, initialCategory: Category.dining);
            if (o != null && mounted) _next();
          },
          icon: const Icon(Icons.edit),
          label: const Text('記一筆'),
        ),
        secondary: TextButton(onPressed: _next, child: const Text('先跳過')),
      );

  Widget _done() {
    final pet = ref.watch(petProvider).value;
    final tasks = (ref.watch(tasksProvider).value ?? const [])
        .where((t) => t.def.kind == TaskKind.newbie)
        .toList();
    return _frame(
      emoji: pet == null ? '🎉' : '${pet.type.emoji}👋',
      title: '準備好了！',
      body: '${pet?.name ?? '寵物'} 會陪你一起記帳。\n完成新手任務可以拿到金幣和道具：',
      content: Card(
        margin: EdgeInsets.zero,
        child: Column(children: [
          for (final t in tasks)
            ListTile(
              dense: true,
              leading: Icon(t.completed ? Icons.task_alt : Icons.radio_button_unchecked,
                  color: t.completed ? Colors.green : null),
              title: Text(t.def.name),
              trailing: Text('🪙 ${t.def.rewardCoins}'),
            ),
        ]),
      ),
      primary: FilledButton(onPressed: _finish, child: const Text('開始養寵物')),
    );
  }
}
