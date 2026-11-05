import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pt_rules.dart';
import '../services/app_services.dart';
import '../state/providers.dart';
import 'home/pet_page.dart';
import 'items/bag_page.dart';
import 'ledger/ledger_page.dart';
import 'more/more_page.dart';
import 'onboarding/onboarding_page.dart';
import 'tasks/tasks_page.dart';
import 'widgets/common.dart';

class MoneyPetApp extends StatelessWidget {
  const MoneyPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '錢寵',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Gate(),
    );
  }
}

/// 依照是否完成 Onboarding 決定首頁。
class _Gate extends ConsumerWidget {
  const _Gate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // skipLoadingOnReload：資料重查時保留舊畫面，不要閃回 loading（否則 Onboarding 會被重建）。
    return settings.when(
      skipLoadingOnReload: true,
      data: (s) => s.onboardingDone ? const HomeShell() : const OnboardingPage(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('無法讀取資料：$e'))),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  var _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onResume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  /// 回到前景：推進寵物時間、結算上個月。
  Future<void> _onResume() async {
    final report = await runAction(context, ref, (s) => s.onAppResume());
    if (report == null || !mounted) return;
    if (report.settlements.isNotEmpty) await _showSettlement(report);
  }

  Future<void> _showSettlement(StartupReport report) {
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('月底結算'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final (month, r, awarded) in report.settlements) ...[
              Text(month, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (r.noPtPenalty)
                const Text('😿 超過半數類別超支，這個月的結算 PT 沒有了。')
              else ...[
                for (final cat in r.categories)
                  Text('${cat.group.label}：${cat.overspent ? '超支' : '省下 ${cat.saved} 元'}'
                      '${cat.ptDeci > 0 ? ' → ${formatPt(cat.ptDeci)} PT' : ''}'),
                if (r.totalBudget != null)
                  Text('總額：${r.totalPtDeci > 0 ? '省下 → ${formatPt(r.totalPtDeci)} PT' : '沒有省到'}'),
                if (r.isDoubleReward) const Text('🎊 兩層都省到，雙重獎勵！'),
                const SizedBox(height: 4),
                Text('獲得 ⭐ ${formatPt(awarded)} PT'
                    '${awarded < r.grossPtDeci ? '（已達每月上限）' : ''}'),
              ],
              const SizedBox(height: 12),
            ],
            if (report.budgetsCarriedOver) const Text('本月預算已沿用上個月的設定。'),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('好'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final claimable = (ref.watch(tasksProvider).value ?? const []).where((t) => t.claimable).length;
    const pages = [PetPage(), LedgerPage(), BagPage(), TasksPage(), MorePage()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.pets_outlined), selectedIcon: Icon(Icons.pets), label: '寵物'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '記帳'),
          const NavigationDestination(icon: Icon(Icons.backpack_outlined), selectedIcon: Icon(Icons.backpack), label: '道具'),
          NavigationDestination(
            icon: Badge(isLabelVisible: claimable > 0, label: Text('$claimable'), child: const Icon(Icons.flag_outlined)),
            selectedIcon: const Icon(Icons.flag),
            label: '任務',
          ),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: '更多'),
        ],
      ),
    );
  }
}
