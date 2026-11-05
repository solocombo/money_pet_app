import 'dart:convert';

import '../data/database.dart';
import '../data/models.dart';
import 'context.dart';

const String backupFormat = 'money_pet_backup';
const int backupFormatVersion = 1;

/// 備份 / 還原。
///
/// - JSON：完整備份（所有資料表），用於還原。
/// - CSV：記帳明細，給使用者用 Excel 查看。
///
/// 之後的 Google Drive 備份會直接上傳這兩個檔案。
class BackupService {
  BackupService(this.ctx);
  final ServiceContext ctx;

  Future<String> exportJson() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in allTables) {
      tables[t] = await ctx.db.query(t);
    }
    return const JsonEncoder.withIndent(' ').convert({
      'format': backupFormat,
      'formatVersion': backupFormatVersion,
      'schemaVersion': schemaVersion,
      'exportedAt': ctx.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// 從 JSON 還原。**會覆蓋目前所有資料**。格式錯誤時不會動到現有資料。
  Future<BackupSummary> importJson(String json) async {
    final Map<String, Object?> root;
    try {
      root = (jsonDecode(json) as Map).cast<String, Object?>();
    } catch (_) {
      throw const UserError('檔案格式不正確');
    }
    if (root['format'] != backupFormat) throw const UserError('這不是錢寵的備份檔');
    final v = root['schemaVersion'];
    if (v is! int || v > schemaVersion) {
      throw const UserError('備份檔來自較新版本的 APP，請先更新 APP');
    }
    final tables = (root['tables'] as Map?)?.cast<String, Object?>();
    if (tables == null) throw const UserError('備份檔內容不完整');

    var rowCount = 0;
    await ctx.db.transaction((txn) async {
      for (final t in allTables) {
        await txn.delete(t);
      }
      // allTables 是子表在前；插入時反過來，父表先進。
      for (final t in allTables.reversed) {
        final rows = tables[t];
        if (rows is! List) continue;
        for (final r in rows) {
          await txn.insert(t, (r as Map).cast<String, Object?>());
          rowCount++;
        }
      }
    });
    // 舊版 schema 的備份：這裡之後加資料轉換。
    return BackupSummary(
      rows: rowCount,
      exportedAt: DateTime.tryParse(root['exportedAt'] as String? ?? ''),
    );
  }

  /// 記帳明細 CSV（含 BOM，Excel 開中文才不會亂碼）。
  Future<String> exportTransactionsCsv() async {
    final methods = {
      for (final r in await ctx.db.query('payment_methods'))
        r['id'] as String: r['name'] as String,
    };
    final rows = await ctx.db.query('transactions', orderBy: 'occurred_at');
    final buf = StringBuffer('﻿')
      ..writeln('日期,時間,類型,類別,金額,省下金額,支付工具,備註');
    for (final r in rows) {
      final t = Txn.fromRow(r);
      final d = t.occurredAt;
      String two(int x) => x.toString().padLeft(2, '0');
      buf.writeln([
        '${d.year}-${two(d.month)}-${two(d.day)}',
        '${two(d.hour)}:${two(d.minute)}',
        t.isExpense ? '支出' : '收入',
        t.categoryLabel,
        t.amount,
        t.savedAmount,
        methods[t.paymentMethodId] ?? '',
        t.note ?? '',
      ].map(_csvCell).join(','));
    }
    return buf.toString();
  }

  static String _csvCell(Object v) {
    final s = v.toString();
    if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    // 避免 Excel 把 =、+、-、@ 開頭的內容當公式執行
    if (s.isNotEmpty && '=+-@'.contains(s[0]) && v is! num) return "'$s";
    return s;
  }
}

class BackupSummary {
  const BackupSummary({required this.rows, this.exportedAt});
  final int rows;
  final DateTime? exportedAt;
}
