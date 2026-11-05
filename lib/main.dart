import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/db_open.dart';
import 'platform/local_notifications.dart';
import 'services/app_services.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW');
  final AppServices services;
  try {
    services = AppServices(await openAppDatabase());
  } catch (e) {
    // 資料庫打不開（例如金鑰儲存區異常）：顯示錯誤，而不是白屏。
    runApp(_StartupError(error: e));
    return;
  }
  runApp(ProviderScope(
    overrides: [
      servicesProvider.overrideWithValue(services),
      notificationSchedulerProvider.overrideWithValue(LocalNotificationScheduler()),
    ],
    child: const MoneyPetApp(),
  ));
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('😿', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                const Text('無法開啟資料', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('請重新開啟 APP。如果一直發生，請聯絡開發者並附上下面的錯誤訊息。',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                SelectableText('$error', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
        ),
      );
}
