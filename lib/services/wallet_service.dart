import 'package:sqflite_common/sqlite_api.dart';

import '../domain/date_utils.dart';
import '../domain/pt_rules.dart';
import 'context.dart';

/// PT 來源。`capped` 為 true 的來源會計入每月上限。
enum PtSource {
  income(capped: true),
  saved(capped: true),
  settlement(capped: true),

  /// 刪除交易時退回已發的 PT（負數），同樣計入上限，讓額度回補。
  reversal(capped: true),
  goal(capped: false),
  redeem(capped: false),
  convert(capped: false);

  const PtSource({required this.capped});
  final bool capped;
}

enum CoinSource { task, noSpend, shop, sell, convert, reversal, ad }

/// 金幣與 PT。餘額 = log 加總，log 是唯一真相來源。
class WalletService {
  WalletService(this.ctx);
  final ServiceContext ctx;

  Future<int> coinBalance([DatabaseExecutor? ex]) =>
      sumInt(ex ?? ctx.db, 'SELECT SUM(amount) FROM coin_log');

  Future<int> ptBalanceDeci([DatabaseExecutor? ex]) =>
      sumInt(ex ?? ctx.db, 'SELECT SUM(amount) FROM pt_log');

  /// 某月已計入上限的 PT（deci）。
  Future<int> cappedEarnedInPeriod(String period, [DatabaseExecutor? ex]) {
    final sources = PtSource.values.where((s) => s.capped).map((s) => "'${s.name}'");
    return sumInt(
      ex ?? ctx.db,
      'SELECT SUM(amount) FROM pt_log WHERE period = ? AND source IN (${sources.join(',')})',
      [period],
    );
  }

  Future<void> addCoins(DatabaseExecutor ex, CoinSource source, int amount,
      {String? note}) async {
    if (amount == 0) return;
    await ex.insert('coin_log', {
      'source': source.name,
      'amount': amount,
      'note': note,
      'created_at': ctx.nowMs(),
    });
  }

  /// 寫入 PT。capped 來源會先套用每月上限，回傳實際入帳的 deci-PT。
  Future<int> addPt(
    DatabaseExecutor ex,
    PtSource source,
    int deci, {
    required String period,
    required PtRates rates,
    String? note,
    String? refId,
  }) async {
    var amount = deci;
    if (source.capped && deci > 0) {
      amount = applyMonthlyCap(
        requestedDeci: deci,
        alreadyEarnedDeci: await cappedEarnedInPeriod(period, ex),
        capDeci: rates.monthlyCapDeci,
      );
    }
    if (amount == 0) return 0;
    await ex.insert('pt_log', {
      'source': source.name,
      'amount': amount,
      'period': period,
      'note': note,
      'ref_id': refId,
      'created_at': ctx.nowMs(),
    });
    return amount;
  }

  /// PT → 金幣（單向）。1 PT = 10 金幣，也就是 1 deci-PT = 1 金幣。
  Future<void> convertPtToCoins(int deci) async {
    if (deci <= 0) throw const UserError('請輸入要轉換的 PT');
    await ctx.db.transaction((txn) async {
      final bal = await ptBalanceDeci(txn);
      if (bal < deci) throw const UserError('PT 不足');
      final period = monthKey(ctx.now());
      await txn.insert('pt_log', {
        'source': PtSource.convert.name,
        'amount': -deci,
        'period': period,
        'note': '轉換成金幣',
        'created_at': ctx.nowMs(),
      });
      await addCoins(txn, CoinSource.convert, deci, note: 'PT 轉換');
    });
  }

  Future<List<Map<String, Object?>>> recentPtLog({int limit = 50}) =>
      ctx.db.query('pt_log', orderBy: 'id DESC', limit: limit);
}
