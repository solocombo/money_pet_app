import 'package:sqflite_common/sqlite_api.dart';

import '../data/app_settings.dart';
import 'context.dart';

class SettingsService {
  SettingsService(this.ctx);
  final ServiceContext ctx;

  static const _key = 'settings';

  Future<AppSettings> load([DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db)
        .query('app_settings', where: 'key = ?', whereArgs: [_key]);
    return AppSettings.decode(rows.isEmpty ? null : rows.first['value'] as String);
  }

  Future<void> save(AppSettings s, [DatabaseExecutor? ex]) =>
      setRaw(_key, s.encode(), ex);

  Future<AppSettings> update(AppSettings Function(AppSettings) f) async {
    final next = f(await load());
    await save(next);
    return next;
  }

  Future<String?> getRaw(String key, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db)
        .query('app_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setRaw(String key, String value, [DatabaseExecutor? ex]) =>
      (ex ?? ctx.db).insert('app_settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
}
