import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/premium_service.dart';
import '../../state/providers.dart';

final _priceProvider = FutureProvider<String?>((ref) => ref.watch(purchaseGatewayProvider).price());

class PremiumPage extends ConsumerWidget {
  const PremiumPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider).value ?? false;
    final price = ref.watch(_priceProvider).value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('進階版')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Center(child: Text('👑', style: TextStyle(fontSize: 72))),
        const SizedBox(height: 8),
        Text(premium ? '你已經是進階版玩家' : '一次買斷，永久使用',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(premium ? '謝謝你的支持！' : '沒有訂閱，不會自動扣款。基本功能永遠免費。',
            textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
        const SizedBox(height: 24),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final p in premiumPerks)
              ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(p)),
            const ListTile(
              leading: Icon(Icons.schedule, color: Colors.grey),
              title: Text('即將推出：拼接款 / 惡搞款寵物提前解鎖、更多外觀、進階報表'),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        if (!premium) ...[
          FilledButton(
            onPressed: () async {
              final gw = ref.read(purchaseGatewayProvider);
              if (!await gw.isAvailable()) {
                if (context.mounted) toast(context, '目前無法連線到商店，請確認已登入 Google Play / App Store');
                return;
              }
              final started = await gw.buy();
              if (!started && context.mounted) toast(context, '無法開始購買，請稍後再試');
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('以 ${price ?? 'NT\$90'} 解鎖', style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await ref.read(purchaseGatewayProvider).restore();
              if (context.mounted) toast(context, '已送出恢復購買要求');
            },
            child: const Text('恢復購買（換手機或重裝時）'),
          ),
        ],
      ]),
    );
  }
}
