import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/enums.dart';
import '../../domain/items.dart';
import '../../domain/recipes.dart';
import '../../services/ad_reward_service.dart';
import '../../services/inventory_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class BagPage extends StatelessWidget {
  const BagPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const GText('道具'),
            actions: const [CoinChip()],
            bottom: const TabBar(tabs: [
              Tab(text: '背包'),
              Tab(text: '合成'),
              Tab(text: '商店'),
              Tab(text: '圖鑑'),
            ]),
          ),
          body: const TabBarView(children: [_Inventory(), _Crafting(), _Shop(), _Collection()]),
        ),
      );
}

class _ItemIcon extends StatelessWidget {
  const _ItemIcon(this.item, {this.size = 32, this.silhouette = false});
  final ItemDef item;
  final double size;
  final bool silhouette;
  @override
  Widget build(BuildContext context) {
    final color = rarityColor(item.rarity);
    return Container(
      width: size + 20,
      height: size + 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: silhouette ? 0.2 : 0.8), width: 2),
        color: color.withValues(alpha: silhouette ? 0.03 : 0.08),
      ),
      child: silhouette
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.black26, BlendMode.srcIn),
              child: Text(item.emoji, style: TextStyle(fontSize: size)),
            )
          : Text(item.emoji, style: TextStyle(fontSize: size)),
    );
  }
}

class _Inventory extends ConsumerWidget {
  const _Inventory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(ref.watch(inventoryProvider), builder: (list) {
      if (list.isEmpty) {
        return const EmptyHint('背包是空的。每記一筆帳都會隨機獲得一個道具！', icon: Icons.backpack_outlined);
      }
      return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        for (final e in list)
          Card(
            child: ListTile(
              leading: _ItemIcon(e.item),
              title: Text('${e.item.name} ×${e.quantity}'),
              subtitle: Text('${e.item.rarity.label} · ${e.item.effectText}'),
              onTap: () => _showActions(context, ref, e),
            ),
          ),
      ]);
    });
  }

  void _showActions(BuildContext context, WidgetRef ref, InventoryEntry e) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: _ItemIcon(e.item, size: 40),
            title: Text(e.item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${e.item.description}\n${e.item.effectText}'
                '${e.item.craftedOnly ? '' : _usedIn(e.item.id)}'),
            isThreeLine: true,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.pets),
            title: const Text('給寵物使用'),
            onTap: () async {
              Navigator.pop(c);
              final r = await runAction(context, ref, (s) => s.pets.useItem(e.item.id));
              if (r != null && context.mounted) {
                toast(context, '${e.item.emoji} ${r.message}');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: Text('賣掉換 🪙 ${e.item.sellPrice}'),
            onTap: () async {
              Navigator.pop(c);
              await runAction(context, ref, (s) => s.inventory.sell(e.item.id),
                  successMessage: '賣出 ${e.item.name}，獲得 🪙 ${e.item.sellPrice}');
            },
          ),
        ]),
      ),
    );
  }
}

String _usedIn(String itemId) {
  final names = [
    for (final r in recipes)
      if (r.ingredients.containsKey(itemId) && r.requiredWisdomLevel == 1) r.result.name,
  ];
  return names.isEmpty ? '' : '\n可合成：${names.join('、')}';
}

class _Crafting extends ConsumerWidget {
  const _Crafting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(petProvider).value;
    final insane = pet?.stats.isInsane ?? false;
    final level = pet?.stats.wisdomLevel ?? 1;
    return AsyncView(ref.watch(inventoryProvider), builder: (inv) {
      final have = {for (final e in inv) e.item.id: e.quantity};
      final sorted = [...recipes]
        ..sort((a, b) {
          final ca = craftableCount(a, have) > 0 ? 0 : 1;
          final cb = craftableCount(b, have) > 0 ? 0 : 1;
          return ca.compareTo(cb);
        });
      return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: GText(
            insane ? '……牠盯著材料發呆，什麼都做不出來。' : '把記帳拿到的食材合成成品，效果更好！',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final r in sorted) _RecipeCard(recipe: r, have: have, wisdomLevel: level, disabled: insane),
      ]);
    });
  }
}

class _RecipeCard extends ConsumerWidget {
  const _RecipeCard({
    required this.recipe,
    required this.have,
    required this.wisdomLevel,
    required this.disabled,
  });
  final Recipe recipe;
  final Map<String, int> have;
  final int wisdomLevel;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = recipe.result;
    final locked = wisdomLevel < recipe.requiredWisdomLevel;
    final can = craftableCount(recipe, have);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _ItemIcon(result, silhouette: locked),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(locked ? '？？？' : result.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  locked ? '寵物智慧 Lv${recipe.requiredWisdomLevel} 解鎖' : '${result.rarity.label} · ${result.effectText}',
                  style: TextStyle(color: locked ? Colors.grey : rarityColor(result.rarity), fontSize: 12),
                ),
              ]),
            ),
            FilledButton(
              onPressed: locked || disabled || can == 0
                  ? null
                  : () async {
                      final item = await runAction(context, ref, (s) => s.inventory.craft(recipe.id));
                      if (item != null && context.mounted) {
                        toast(context, '合成成功！獲得 ${item.emoji} ${item.name}');
                      }
                    },
              child: Text(can > 0 && !locked ? '合成' : '材料不足'),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in recipe.ingredients.entries)
              Builder(builder: (_) {
                final item = itemById(e.key)!;
                final n = have[e.key] ?? 0;
                final enough = n >= e.value;
                return Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Text(item.emoji),
                  label: Text('${item.name} $n/${e.value}',
                      style: TextStyle(color: enough ? null : Colors.red)),
                );
              }),
          ]),
        ]),
      ),
    );
  }
}

class _Shop extends ConsumerWidget {
  const _Shop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insane = ref.watch(petProvider).value?.stats.isInsane ?? false;
    return AsyncView(ref.watch(shopProvider), builder: (slots) {
      return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: GText(
            insane ? '……商店的門關著。裡面好像有什麼在看著你。' : '每天都會換貨，最後一格是限定商品（7 折）！',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const _AdCoinsCard(),
        for (final st in slots) _ShopTile(state: st, disabled: insane),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('金幣可以從任務、本日無支出、賣道具，或在任務頁用 PT 換取（1 PT = 10 金幣）。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ]);
    });
  }
}

class _AdCoinsCard extends ConsumerWidget {
  const _AdCoinsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = ref.watch(adCoinsRemainingProvider).value ?? 0;
    return Card(
      child: ListTile(
        leading: const Text('📺', style: TextStyle(fontSize: 26)),
        title: const Text('看廣告領金幣'),
        subtitle: Text('每次 🪙 $adCoinReward，今天還剩 $left 次（完全自願）'),
        trailing: FilledButton.tonal(
          onPressed: left <= 0
              ? null
              : () async {
                  final watched = await ref.read(adGatewayProvider).show();
                  if (!context.mounted) return;
                  if (!watched) {
                    toast(context, '廣告沒有看完或暫時無法載入，等等再試試');
                    return;
                  }
                  await runAction(context, ref, (s) => s.ads.claimCoins(),
                      successMessage: '謝謝支持！🪙 +$adCoinReward');
                },
          child: const Text('觀看'),
        ),
      ),
    );
  }
}

class _ShopTile extends ConsumerWidget {
  const _ShopTile({required this.state, required this.disabled});
  final ShopSlotState state;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = state.slot;
    final item = slot.item;
    return Card(
      shape: slot.isLimited
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade600, width: 2))
          : null,
      child: ListTile(
        leading: _ItemIcon(item),
        title: Row(children: [
          Flexible(child: Text(item.name)),
          if (slot.isLimited) ...[
            const SizedBox(width: 6),
            const Chip(label: Text('今日限定'), visualDensity: VisualDensity.compact),
          ],
        ]),
        subtitle: Text('${item.rarity.label} · ${item.effectText}'),
        trailing: FilledButton(
          onPressed: state.purchased || disabled
              ? null
              : () => runAction(context, ref, (s) => s.inventory.buy(slot.slot),
                  successMessage: '買到 ${item.emoji} ${item.name}！'),
          child: Text(state.purchased ? '已購買' : '🪙 ${slot.price}'),
        ),
      ),
    );
  }
}

class _Collection extends ConsumerWidget {
  const _Collection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(ref.watch(collectionProvider), builder: (got) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('已收集 ${got.length} / ${itemCatalog.length}',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final r in Rarity.values.reversed) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('${r.label}（掉落率 ${r.dropWeight}%）',
                style: TextStyle(color: rarityColor(r), fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(children: [
              for (final item in itemCatalog.where((i) => i.rarity == r))
                _CollectionCell(item: item, obtainedAt: got[item.id]),
            ]),
          ),
        ],
        const SizedBox(height: 32),
      ]);
    });
  }
}

class _CollectionCell extends StatelessWidget {
  const _CollectionCell({required this.item, this.obtainedAt});
  final ItemDef item;
  final DateTime? obtainedAt;

  @override
  Widget build(BuildContext context) {
    final known = obtainedAt != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(known ? item.name : '？？？'),
          content: Text(known
              ? '${item.description}\n\n${item.effectText}\n'
                  '第一次獲得：${DateFormat('yyyy/M/d').format(obtainedAt!)}'
              : '還沒獲得過這個道具。繼續記帳吧！'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('關閉'))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 72,
          child: Column(children: [
            _ItemIcon(item, silhouette: !known),
            const SizedBox(height: 2),
            Text(known ? item.name : '？？？',
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
