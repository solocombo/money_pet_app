import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/models.dart';
import '../domain/date_utils.dart';
import '../services/app_services.dart';
import '../services/bill_service.dart';
import '../services/context.dart';
import '../services/inventory_service.dart';
import '../services/ledger_service.dart';
import '../services/notification_service.dart';
import '../services/task_service.dart';

/// 在 main() 用 overrideWithValue 注入。
final servicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('servicesProvider must be overridden'),
);

/// 平台通知排程器。main() 會換成真正的 flutter_local_notifications 版本。
final notificationSchedulerProvider =
    Provider<NotificationScheduler>((ref) => NoopScheduler());

final notificationServiceProvider = Provider<NotificationService>((ref) =>
    NotificationService(ref.watch(servicesProvider), ref.watch(notificationSchedulerProvider)));

/// 資料版本號。任何寫入後 +1，所有讀取 provider 都會重新查詢。
/// 資料量小（純本地），這樣比精細追蹤每張表簡單且不易出錯。
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

/// 建立一個「資料變動就重查」的 FutureProvider。
FutureProvider<T> _q<T>(Future<T> Function(AppServices s) f) =>
    FutureProvider<T>((ref) {
      ref.watch(dataVersionProvider);
      return f(ref.watch(servicesProvider));
    });

final settingsProvider = _q<AppSettings>((s) => s.settings.load());
final petProvider = _q<Pet?>((s) => s.pets.activePet());
final conditionsProvider = _q<List<PetCondition>>((s) => s.pets.activeConditions());
final coinsProvider = _q<int>((s) => s.wallet.coinBalance());
final ptProvider = _q<int>((s) => s.wallet.ptBalanceDeci());
final noSpendTodayProvider = _q<bool>((s) => s.ledger.isNoSpendToday());
final recentTxnProvider = _q<List<Txn>>((s) => s.ledger.recentTransactions());
final inventoryProvider = _q<List<InventoryEntry>>((s) => s.inventory.list());
final collectionProvider = _q<Map<String, DateTime>>((s) => s.inventory.collection());
final shopProvider = _q<List<ShopSlotState>>((s) => s.inventory.todayShop());
final tasksProvider = _q<List<TaskStatus>>((s) => s.tasks.statuses());
final rewardsProvider = _q<List<Reward>>((s) => s.rewards.rewards());
final goalsProvider = _q<List<FinancialGoal>>((s) => s.rewards.goals());
final assetsProvider = _q<List<AssetAccount>>((s) => s.assets.accounts());
final oldestAssetUpdateProvider = _q<DateTime?>((s) => s.assets.oldestUpdate());
final billsUpcomingProvider = _q<List<BillDue>>((s) => s.bills.upcoming());
final billsDueSoonProvider = _q<List<BillDue>>((s) => s.bills.dueSoon());
final paymentMethodsProvider = _q<List<PaymentMethod>>((s) => s.bills.paymentMethods());
final paymentUsageProvider = _q<List<PaymentMethodUsage>>((s) => s.bills.paymentMethodUsage());

final currentMonthProvider = Provider<String>(
    (ref) => monthKey(ref.watch(servicesProvider).ctx.now()));

final monthSummaryProvider = FutureProvider.family<MonthSummary, String>((ref, month) {
  ref.watch(dataVersionProvider);
  return ref.watch(servicesProvider).ledger.summary(month);
});

final monthTxnProvider = FutureProvider.family<List<Txn>, String>((ref, month) {
  ref.watch(dataVersionProvider);
  return ref.watch(servicesProvider).ledger.transactionsInMonth(month);
});

/// 寵物失控且沒有關閉亂碼效果 → UI 部分文字變亂碼。
final garbleProvider = Provider<bool>((ref) {
  final insane = ref.watch(petProvider).value?.stats.isInsane ?? false;
  final disabled = ref.watch(settingsProvider).value?.disableGarble ?? false;
  return insane && !disabled;
});

/// 執行一個會寫入資料的動作：
/// - [UserError] 以 SnackBar 顯示
/// - 成功後 bump 資料版本
/// - 回傳結果；失敗回傳 null
Future<T?> runAction<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function(AppServices s) action, {
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final result = await action(ref.read(servicesProvider));
    ref.read(dataVersionProvider.notifier).bump();
    if (successMessage != null) _show(messenger, successMessage);
    return result;
  } on UserError catch (e) {
    _show(messenger, e.message);
    return null;
  }
}

/// 顯示提示。先清掉舊的，避免連續操作時訊息排隊很久。
void toast(BuildContext context, String message) =>
    _show(ScaffoldMessenger.maybeOf(context), message);

void _show(ScaffoldMessengerState? m, String message) {
  m
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
