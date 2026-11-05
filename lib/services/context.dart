import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

/// 所有 service 共用的依賴。測試時可注入固定時間與亂數。
class ServiceContext {
  ServiceContext({
    required this.db,
    DateTime Function()? clock,
    Random? random,
  })  : clock = clock ?? DateTime.now,
        random = random ?? Random();

  final Database db;
  final DateTime Function() clock;
  final Random random;
  static const _uuid = Uuid();

  DateTime now() => clock();
  int nowMs() => clock().millisecondsSinceEpoch;
  String newId() => _uuid.v4();
}

/// 使用者操作錯誤（例如餘額不足），UI 直接顯示 [message]。
class UserError implements Exception {
  const UserError(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<int> sumInt(DatabaseExecutor ex, String sql, [List<Object?>? args]) async {
  final rows = await ex.rawQuery(sql, args);
  final v = rows.first.values.first;
  return (v as num?)?.toInt() ?? 0;
}
