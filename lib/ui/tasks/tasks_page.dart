import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/date_utils.dart';
import '../../domain/pt_rules.dart';
import '../../domain/tasks.dart';
import '../../services/task_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const GText('任務與獎勵'),
            actions: const [CoinChip()],
            bottom: const TabBar(tabs: [
              Tab(text: '任務'),
              Tab(text: '財務目標'),
              Tab(text: '獎勵櫃'),
            ]),
          ),
          body: const TabBarView(children: [_Tasks(), _Goals(), RewardsView()]),
        ),
      );
}

class _Tasks extends ConsumerWidget {
  const _Tasks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(ref.watch(tasksProvider), builder: (list) {
      final svc = ref.read(servicesProvider).tasks;
      final newbie = list.where((t) => t.def.kind == TaskKind.newbie).toList();
      final allNewbieClaimed = newbie.every((t) => t.claimed);
      return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        for (final kind in TaskKind.values)
          if (!(kind == TaskKind.newbie && allNewbieClaimed)) ...[
            SectionTitle(kind.label),
            Card(
              child: Column(children: [
                for (final t in list.where((t) => t.def.kind == kind))
                  _TaskTile(status: t, rewardText: svc.rewardText(t.def)),
              ]),
            ),
          ],
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('任務只給金幣和道具。PT 只能靠省錢和完成財務目標獲得。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ]);
    });
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.status, required this.rewardText});
  final TaskStatus status;
  final String rewardText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = status;
    final Widget trailing;
    if (t.claimed) {
      trailing = const Icon(Icons.check_circle, color: Colors.green);
    } else if (t.claimable) {
      trailing = FilledButton(
        onPressed: () => runAction(context, ref, (s) => s.tasks.claim(t.def.id, t.period),
            successMessage: '領取獎勵：$rewardText'),
        child: const Text('領取'),
      );
    } else {
      trailing = Text(rewardText, style: Theme.of(context).textTheme.bodySmall);
    }
    return ListTile(
      leading: Icon(
        t.completed ? Icons.task_alt : Icons.radio_button_unchecked,
        color: t.completed ? Colors.green : null,
      ),
      title: GText(t.def.name),
      subtitle: Text(t.hint ?? t.def.description),
      trailing: trailing,
    );
  }
}

class _Goals extends ConsumerWidget {
  const _Goals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = startOfDay(ref.watch(servicesProvider).ctx.now());
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal',
        onPressed: () => showGoalEditor(context, ref),
        icon: const Icon(Icons.flag),
        label: const Text('新目標'),
      ),
      body: AsyncView(ref.watch(goalsProvider), builder: (goals) {
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('自己承諾、自己定價：設定一個財務相關的小目標，完成後手動打勾領取 PT。'
                '\n例如「這週自己帶便當三次」、「本月不買手搖飲」。'),
          ),
          if (goals.isEmpty) const EmptyHint('還沒有目標', icon: Icons.flag_outlined),
          for (final g in goals) _GoalTile(goal: g, today: today),
        ]);
      }),
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const _GoalTile({required this.goal, required this.today});
  final FinancialGoal goal;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = goal;
    final deadline = parseDateKey(g.deadline);
    final expired = !g.isCompleted && today.isAfter(deadline);
    final status = g.isCompleted
        ? '已完成 ${DateFormat('M/d').format(g.completedAt!)}'
        : (expired ? '已過期' : '截止 ${DateFormat('M/d (E)', 'zh_TW').format(deadline)}');
    return Card(
      child: ListTile(
        leading: Text(g.isCompleted ? '🏁' : (expired ? '⌛' : '🚩'), style: const TextStyle(fontSize: 24)),
        title: Text(g.name,
            style: TextStyle(decoration: g.isCompleted ? TextDecoration.lineThrough : null)),
        subtitle: Text([if (g.description != null) g.description!, status, '⭐ ${formatPt(g.ptRewardDeci)} PT'].join('\n')),
        isThreeLine: true,
        trailing: g.isCompleted || expired
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => runAction(context, ref, (s) => s.rewards.deleteGoal(g.id)),
              )
            : FilledButton(
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: '完成「${g.name}」了嗎？', message: '誠實面對自己喔！', confirm: '完成了');
                  if (!ok || !context.mounted) return;
                  await runAction(context, ref, (s) => s.rewards.completeGoal(g.id),
                      successMessage: '目標達成！⭐ +${formatPt(g.ptRewardDeci)} PT');
                },
                child: const Text('完成'),
              ),
        onLongPress: () async {
          if (await confirmDialog(context, title: '刪除目標？', confirm: '刪除', danger: true) &&
              context.mounted) {
            await runAction(context, ref, (s) => s.rewards.deleteGoal(g.id));
          }
        },
      ),
    );
  }
}

Future<void> showGoalEditor(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final desc = TextEditingController();
  final pt = TextEditingController(text: '100');
  final now = ref.read(servicesProvider).ctx.now();
  final mondayFirst = ref.read(settingsProvider).value?.weekStartsMonday ?? true;
  // 一週從星期一開始 → 週日結束；從星期日開始 → 週六結束。
  final weekEnd = DateTime(now.year, now.month,
      now.day + (mondayFirst ? 7 - now.weekday : 6 - now.weekday % 7));
  final monthEnd = DateTime(now.year, now.month + 1, 0);
  var deadline = weekEnd;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('新的財務目標', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: '目標名稱', hintText: '這週自己帶便當三次')),
          const SizedBox(height: 8),
          TextField(controller: desc, decoration: const InputDecoration(labelText: '說明（選填）')),
          const SizedBox(height: 8),
          TextField(
            controller: pt,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalOnly,
            decoration: const InputDecoration(labelText: '完成可獲得的 PT（自己決定）'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('本週'), selected: deadline == weekEnd, onSelected: (_) => setState(() => deadline = weekEnd)),
            ChoiceChip(label: const Text('本月'), selected: deadline == monthEnd, onSelected: (_) => setState(() => deadline = monthEnd)),
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Text(deadline == weekEnd || deadline == monthEnd ? '自訂日期' : DateFormat('M/d').format(deadline)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: c, initialDate: deadline, firstDate: now, lastDate: DateTime(now.year + 2));
                if (d != null) setState(() => deadline = d);
              },
            ),
          ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final deci = parsePt(pt.text) ?? 0;
              final ok = await runAction(c, ref, (s) async {
                await s.rewards.addGoal(name: name.text, description: desc.text, ptRewardDeci: deci, deadline: deadline);
                return true;
              });
              if (ok == true && c.mounted) Navigator.pop(c);
            },
            child: const Text('建立目標'),
          ),
        ]),
      );
    }),
  );
}

/// 獎勵櫃（也用在 Onboarding 之後的任務頁）。
class RewardsView extends ConsumerWidget {
  const RewardsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pt = ref.watch(ptProvider).value ?? 0;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reward',
        onPressed: () => showRewardEditor(context, ref),
        icon: const Icon(Icons.card_giftcard),
        label: const Text('新獎勵'),
      ),
      body: AsyncView(ref.watch(rewardsProvider), builder: (list) {
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Card(
            child: ListTile(
              leading: const Text('⭐', style: TextStyle(fontSize: 28)),
              title: Text('${formatPt(pt)} PT', style: Theme.of(context).textTheme.headlineSmall),
              subtitle: const Text('省錢、收入記帳、財務目標都能獲得 PT'),
              trailing: OutlinedButton(
                onPressed: () => _convert(context, ref, pt),
                child: const Text('換金幣'),
              ),
            ),
          ),
          if (list.isEmpty) const EmptyHint('獎勵櫃是空的。放一個想要的現實獎勵吧！', icon: Icons.card_giftcard),
          for (final r in list) _RewardTile(reward: r, balance: pt),
        ]);
      }),
    );
  }

  Future<void> _convert(BuildContext context, WidgetRef ref, int balance) async {
    final v = await promptText(context,
        title: 'PT 換金幣',
        label: '要換多少 PT？',
        hint: '1 PT = 10 金幣，單向不可換回',
        decimal: true);
    final deci = v == null ? null : parsePt(v);
    if (deci == null || deci <= 0 || !context.mounted) return;
    await runAction(context, ref, (s) => s.wallet.convertPtToCoins(deci),
        successMessage: '換到 🪙 $deci');
  }
}

class _RewardTile extends ConsumerWidget {
  const _RewardTile({required this.reward, required this.balance});
  final Reward reward;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reward;
    final progress = (balance / r.ptCostDeci).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.isRedeemed ? '🎉' : '🎁', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: r.isRedeemed ? TextDecoration.lineThrough : null)),
            ),
            Text('${formatPt(r.ptCostDeci)} PT'),
          ]),
          if (!r.isRedeemed) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () async {
                if (await confirmDialog(context, title: '刪除「${r.name}」？', confirm: '刪除', danger: true) &&
                    context.mounted) {
                  await runAction(context, ref, (s) => s.rewards.deleteReward(r.id));
                }
              },
              child: const Text('刪除'),
            ),
            if (r.isRedeemed)
              Text('已兌換 ${DateFormat('yyyy/M/d').format(r.redeemedAt!)}')
            else
              FilledButton(
                onPressed: balance >= r.ptCostDeci
                    ? () async {
                        if (await confirmDialog(context,
                                title: '兌換「${r.name}」？',
                                message: '會扣除 ${formatPt(r.ptCostDeci)} PT。去好好享受吧！',
                                confirm: '兌換') &&
                            context.mounted) {
                          await runAction(context, ref, (s) => s.rewards.redeem(r.id),
                              successMessage: '兌換成功！好好犒賞自己 🎉');
                        }
                      }
                    : null,
                child: const Text('兌換'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// 新增獎勵。回傳是否有新增。
Future<bool> showRewardEditor(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final pt = TextEditingController(text: '500');
  final added = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('新增獎勵'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '獎勵', hintText: '吃一頓大餐'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pt,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalOnly,
          decoration: const InputDecoration(labelText: '需要多少 PT', helperText: '參考：小 500、中 1500、大 5000'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            final ok = await runAction(c, ref, (s) async {
              await s.rewards.addReward(name.text, parsePt(pt.text) ?? 0);
              return true;
            });
            if (ok == true && c.mounted) Navigator.pop(c, true);
          },
          child: const Text('新增'),
        ),
      ],
    ),
  );
  return added ?? false;
}
