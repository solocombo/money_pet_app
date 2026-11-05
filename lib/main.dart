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
  final db = await openAppDatabase();
  runApp(ProviderScope(
    overrides: [
      servicesProvider.overrideWithValue(AppServices(db)),
      notificationSchedulerProvider.overrideWithValue(LocalNotificationScheduler()),
    ],
    child: const MoneyPetApp(),
  ));
}
