import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/enums.dart';
import '../../domain/evolution_diary.dart';
import '../../domain/finance_rules.dart';
import '../../domain/items.dart';
import '../../domain/pet_rules.dart';
import '../../domain/tasks.dart';
import '../../state/providers.dart';
import '../ledger/add_transaction_sheet.dart';
import '../more/bills_page.dart';
import '../more/assets_page.dart';
import 'diary_page.dart';
import 'share_card.dart';
import '../widgets/common.dart';

class PetPage extends ConsumerWidget {
  const PetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(petProvider);
    final garbled = ref.watch(garbleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const GText('錢寵'),
        actions: const [CoinChip()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'pet_add',
        onPressed: () => showAddTransaction(context),
        icon: const Icon(Icons.edit),
        label: const Text('記一筆'),
      ),
      body: AsyncView(pet, builder: (p) {
        if (p == null) return const EmptyHint('還沒有寵物');
        return Desaturate(
          enabled: garbled,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _PetCard(pet: p),
              const _DailyActions(),
              const _Reminders(),
              const _RecentTransactions(),
            ],
          ),
        );
      }),
    );
  }
}

class _PetCard extends ConsumerStatefulWidget {
  const _PetCard({required this.pet});
  final Pet pet;
  @override
  ConsumerState<_PetCard> createState() => _PetCardState();
}

class _PetCardState extends ConsumerState<_PetCard> with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  String? _reaction;

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _poke() async {
    final r = await runAction(context, ref, (s) => s.pets.poke());
    if (r == null || !mounted) return;
    // 失控時動作凍結：只有文字反應，沒有彈跳。
    if (!widget.pet.stats.isInsane) _bounce.forward(from: 0);
    setState(() => _reaction = r.reaction);
    if (r.firstToday) {
      toast(context, '每日戳戳完成！可以到任務頁領取獎勵');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pet;
    final st = p.stats;
    final conditions = ref.watch(conditionsProvider).value ?? const [];
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: GText(p.name,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: '分享',
                icon: const Icon(Icons.ios_share),
                onPressed: () => showShareCard(context, ref, p),
              ),
              IconButton(
                tooltip: '寵物日記',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DiaryPage())),
              ),
              Chip(
                avatar: const Text('🧠'),
                label: GText('智慧 Lv${st.wisdomLevel}'),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            if (p.isEvolved)
              Align(
                alignment: Alignment.centerLeft,
                child: GText('✨ ${evolvedForms[p.type]!.title}',
                    style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
              ),
            GestureDetector(
              onTap: _poke,
              child: AnimatedBuilder(
                animation: _bounce,
                builder: (_, child) {
                  final t = Curves.easeOut.transform(_bounce.value);
                  final dy = -24 * (1 - (2 * t - 1).abs());
                  return Transform.translate(offset: Offset(0, dy), child: child);
                },
                child: _PetSprite(pet: p),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _reaction == null ? '點點寵物跟牠互動' : '${p.name} $_reaction',
                key: ValueKey(_reaction),
                style: TextStyle(color: theme.hintColor),
              ),
            ),
            const SizedBox(height: 12),
            if (st.isInsane)
              _Banner(
                color: Colors.deepPurple,
                icon: '👁️',
                text: '${p.name} 失去理智了。連續記帳 $insaneRecoveryDays 天可以讓牠恢復'
                    '（目前 ${st.insaneStreak} / $insaneRecoveryDays 天）。商店暫停營業。',
              )
            else if (st.isSanWarning)
              const _Banner(
                color: Colors.purple,
                icon: '⚠️',
                text: '理智值偏低，注意衝動消費與深夜記帳。',
              ),
            for (final c in conditions)
              _Banner(
                color: Colors.red,
                icon: '🤒',
                text: '${c.type.label}：${c.type.effect}'
                    '（${DateFormat('M/d').format(c.expiresAt)} 自動康復，或使用藥品）',
              ),
            _EvolutionHint(pet: p),
            for (final a in PetAttribute.values)
              StatBar(
                attribute: a,
                value: st.valueOf(a),
                max: a == PetAttribute.san ? st.sanMax : 100,
                trailing: a == PetAttribute.san
                    ? '${st.san.round()}/${st.sanMax.round()}'
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// 智慧 Lv4 以上才顯示進化進度，避免新手一開始就看到一堆條件。
class _EvolutionHint extends ConsumerWidget {
  const _EvolutionHint({required this.pet});
  final Pet pet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pet.isEvolved || pet.stats.wisdomLevel < 4) return const SizedBox.shrink();
    final now = ref.watch(servicesProvider).ctx.now();
    final blockers =
        evolutionBlockers(stats: pet.stats, createdAt: pet.createdAt, now: now, stage: pet.stage);
    if (blockers.isNotEmpty) {
      return _Banner(color: Colors.amber.shade800, icon: '🥚', text: '進化條件：${blockers.join('、')}');
    }
    final form = evolvedForms[pet.type]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
        onPressed: () async {
          final ok = await confirmDialog(context,
              title: '${pet.name} 準備好進化了！',
              message: '進化成「${form.title}」${form.emoji}\n${form.description}\n\n理智上限 +$evolutionSanBonus。進化後無法還原。',
              confirm: '進化！');
          if (!ok || !context.mounted) return;
          final f = await runAction(context, ref, (s) => s.pets.evolve());
          if (f != null && context.mounted) {
            await showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('${pet.name} 進化成${f.title}了！'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: Text(f.emoji, style: const TextStyle(fontSize: 96)),
                  ),
                  const SizedBox(height: 8),
                  Text(f.description, textAlign: TextAlign.center),
                ]),
                actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('太棒了'))],
              ),
            );
          }
        },
        icon: const Text('✨'),
        label: const Text('可以進化了！'),
      ),
    );
  }
}

class _PetSprite extends StatelessWidget {
  const _PetSprite({required this.pet});
  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final st = pet.stats;
    final sad = PetAttribute.decaying.any((a) => st.valueOf(a) < lowAttributeThreshold);
    // MVP 先用 emoji；之後換 itch.io 像素素材。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            ),
          ),
          Opacity(
            opacity: st.isInsane ? 0.55 : 1,
            child: Text(pet.isEvolved ? evolvedForms[pet.type]!.emoji : pet.type.emoji,
                style: const TextStyle(fontSize: 96)),
          ),
          if (pet.isEvolved && !st.isInsane)
            const Positioned(top: 4, right: 30, child: Text('✨', style: TextStyle(fontSize: 28))),
          if (st.isInsane)
            const Positioned(top: 38, child: Text('◉  ◉', style: TextStyle(fontSize: 18, color: Colors.black54)))
          else if (sad)
            const Positioned(right: 20, top: 20, child: Text('💧', style: TextStyle(fontSize: 28))),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final String icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon),
          const SizedBox(width: 8),
          Expanded(child: GText(text)),
        ]),
      );
}

class _DailyActions extends ConsumerWidget {
  const _DailyActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const [];
    final noSpend = ref.watch(noSpendTodayProvider).value ?? false;
    bool claimed(String id) => tasks.any((t) => t.def.id == id && t.claimed);
    bool completed(String id) => tasks.any((t) => t.def.id == id && t.completed);
    final checkedIn = claimed(TaskIds.dailyCheckIn);
    final recorded = completed(TaskIds.dailyRecord);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: checkedIn
                ? null
                : () async {
                    ItemDef? bonus;
                    final ok = await runAction(
                        context,
                        ref,
                        (s) => s.tasks.completeAndClaim(TaskIds.dailyCheckIn,
                            onBonusItem: (i) => bonus = i));
                    if (ok == true && context.mounted) {
                      final extra = bonus == null ? '' : '，進階版加碼 ${bonus!.emoji} ${bonus!.name}';
                      toast(context, '簽到成功！🪙 +${taskById(TaskIds.dailyCheckIn).rewardCoins}$extra');
                    }
                  },
            icon: Icon(checkedIn ? Icons.check : Icons.event_available),
            label: Text(checkedIn ? '已簽到' : '簽到'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: noSpend || recorded
                ? null
                : () async {
                    final ok = await confirmDialog(context,
                        title: '本日無支出？',
                        message: '今天真的沒有花錢嗎？打卡後飽食值今天只會下降一半，還有少量金幣獎勵。'
                            '\n\n（如果之後又記了支出，打卡會自動取消）');
                    if (!ok || !context.mounted) return;
                    await runAction(context, ref, (s) => s.ledger.checkInNoSpend(),
                        successMessage: '打卡成功！🪙 +$noSpendCoinReward');
                  },
            icon: Icon(noSpend ? Icons.check : Icons.savings_outlined),
            label: Text(noSpend ? '今日無支出 ✓' : (recorded ? '今天已記帳' : '本日無支出')),
          ),
        ),
      ]),
    );
  }
}

class _Reminders extends ConsumerWidget {
  const _Reminders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsDueSoonProvider).value ?? const [];
    final oldest = ref.watch(oldestAssetUpdateProvider).value;
    final usage = ref.watch(paymentUsageProvider).value ?? const [];
    final now = ref.watch(servicesProvider).ctx.now();
    final tiles = <Widget>[];

    for (final b in bills) {
      final days = b.dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
      final when = days < 0 ? '已逾期 ${-days} 天' : (days == 0 ? '今天到期' : '$days 天後到期');
      tiles.add(ListTile(
        leading: const Text('🧾', style: TextStyle(fontSize: 24)),
        title: Text('${b.bill.name} $when'),
        subtitle: Text(b.bill.amount == null ? '金額未定' : formatMoney(b.bill.amount!)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BillsPage())),
      ));
    }
    for (final u in usage.where((u) => u.warning)) {
      tiles.add(ListTile(
        leading: const Text('💳', style: TextStyle(fontSize: 24)),
        title: Text('${u.method.name} 本期已刷 ${formatMoney(u.cycleSpent)}'),
        subtitle: Text('已達額度 ${formatMoney(u.method.creditLimit ?? 0)} 的警戒線'),
      ));
    }
    if (oldest != null && isAssetStale(oldest, now)) {
      tiles.add(ListTile(
        leading: const Text('🏦', style: TextStyle(fontSize: 24)),
        title: const Text('資產資訊超過 3 天沒更新了'),
        subtitle: const Text('更新後可完成固定任務'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssetsPage())),
      ));
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SectionTitle('提醒'),
      Card(child: Column(children: tiles)),
    ]);
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recentTxnProvider).value ?? const <Txn>[];
    return Column(children: [
      const SectionTitle('最近記帳'),
      if (list.isEmpty)
        const EmptyHint('還沒有記帳紀錄，按右下角「記一筆」開始吧！', icon: Icons.edit_note)
      else
        Card(
          child: Column(children: [
            for (final t in list) TxnTile(txn: t, onTap: () => showEditTransaction(context, t)),
          ]),
        ),
    ]);
  }
}

/// 交易列（記帳頁共用）。金額與內容**不套用亂碼**。
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.onTap, this.onLongPress});
  final Txn txn;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final sign = txn.isExpense ? '-' : '+';
    final color = txn.isExpense ? null : Colors.green.shade700;
    final sub = [
      DateFormat('M/d HH:mm').format(txn.occurredAt),
      if (txn.note != null) txn.note!,
      if (txn.savedAmount > 0) '省 ${formatMoney(txn.savedAmount)}',
    ].join(' · ');
    return ListTile(
      leading: Text(txn.categoryEmoji, style: const TextStyle(fontSize: 24)),
      title: Text(txn.categoryLabel),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('$sign${formatMoney(txn.amount)}',
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
