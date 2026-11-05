import '../data/models.dart';
import '../domain/date_utils.dart';
import '../domain/enums.dart';
import '../domain/finance_rules.dart';
import 'context.dart';
import 'ledger_service.dart';

class PaymentMethodUsage {
  const PaymentMethodUsage(this.method, {this.cycleSpent = 0, this.warning = false});
  final PaymentMethod method;

  /// 信用卡本期已刷金額。
  final int cycleSpent;
  final bool warning;
}

/// 逾期幾天內的未繳帳單仍會顯示。
const int overdueWindowDays = 7;

/// 帳單提醒 + 支付工具。
class BillService {
  BillService(this.ctx, this.ledger);
  final ServiceContext ctx;
  final LedgerService ledger;

  // ---- 支付工具 ----

  Future<List<PaymentMethod>> paymentMethods() async {
    final rows = await ctx.db.query('payment_methods',
        where: 'is_archived = 0', orderBy: 'created_at');
    return rows.map(PaymentMethod.fromRow).toList();
  }

  Future<void> savePaymentMethod({
    String? id,
    required String name,
    required PaymentType type,
    int? creditLimit,
    int? billingDay,
    int? dueDay,
  }) async {
    if (name.trim().isEmpty) throw const UserError('請輸入名稱');
    for (final d in [billingDay, dueDay]) {
      if (d != null && (d < 1 || d > 31)) throw const UserError('日期要在 1–31 之間');
    }
    final isCard = type == PaymentType.creditCard;
    final row = {
      'name': name.trim(),
      'type': type.name,
      'credit_limit': isCard ? creditLimit : null,
      'billing_day': isCard ? billingDay : null,
      'due_day': isCard ? dueDay : null,
    };
    if (id == null) {
      await ctx.db.insert('payment_methods',
          {...row, 'id': ctx.newId(), 'created_at': ctx.nowMs()});
    } else {
      await ctx.db.update('payment_methods', row, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// 封存而不是刪除，舊交易的支付工具名稱才不會不見。
  Future<void> archivePaymentMethod(String id) => ctx.db.update(
      'payment_methods', {'is_archived': 1},
      where: 'id = ?', whereArgs: [id]);

  Future<List<PaymentMethodUsage>> paymentMethodUsage() async {
    final s = await ledger.settings.load();
    final out = <PaymentMethodUsage>[];
    for (final m in await paymentMethods()) {
      if (!m.isCreditCard || m.billingDay == null) {
        out.add(PaymentMethodUsage(m));
        continue;
      }
      final (start, end) = creditCardCycle(ctx.now(), m.billingDay!);
      final spent = await sumInt(
        ctx.db,
        "SELECT SUM(amount) FROM transactions WHERE type = 'expense' "
        'AND payment_method_id = ? AND occurred_at >= ? AND occurred_at < ?',
        [m.id, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      );
      out.add(PaymentMethodUsage(
        m,
        cycleSpent: spent,
        warning: isCreditWarning(
            spent: spent,
            creditLimit: m.creditLimit ?? 0,
            warnRatio: s.creditWarnRatio),
      ));
    }
    return out;
  }

  // ---- 帳單 ----

  Future<List<Bill>> bills() async {
    final rows = await ctx.db.query('bills', orderBy: 'due_day');
    return rows.map(Bill.fromRow).toList();
  }

  Future<void> saveBill({
    String? id,
    required String name,
    required BillType type,
    int? amount,
    required int dueDay,
    required int remindDaysBefore,
    required Recurrence recurrence,
    required Category category,
    String? paymentMethodId,
    bool isActive = true,
  }) async {
    if (name.trim().isEmpty) throw const UserError('請輸入帳單名稱');
    if (dueDay < 1 || dueDay > 31) throw const UserError('到期日要在 1–31 之間');
    if (amount != null && amount <= 0) throw const UserError('金額要大於 0');
    final row = {
      'name': name.trim(),
      'type': type.name,
      'amount': amount,
      'due_day': dueDay,
      'remind_days_before': remindDaysBefore.clamp(0, 30),
      'recurrence': recurrence.name,
      'category': category.name,
      'payment_method_id': paymentMethodId,
      'is_active': isActive ? 1 : 0,
    };
    if (id == null) {
      await ctx.db.insert('bills', {
        ...row,
        'id': ctx.newId(),
        'anchor_month': monthKey(ctx.now()),
        'created_at': ctx.nowMs(),
      });
    } else {
      await ctx.db.update('bills', row, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteBill(String id) =>
      ctx.db.delete('bills', where: 'id = ?', whereArgs: [id]);

  /// 所有啟用中帳單的下一次到期日，依到期日排序。
  ///
  /// 若本期已繳，會往後顯示下一期。
  Future<List<BillDue>> upcoming() async {
    final today = ctx.now();
    final out = <BillDue>[];
    for (final b in await bills()) {
      if (!b.isActive) continue;
      // 先看過去 7 天內有沒有逾期未繳的；有就優先顯示它。
      final overdue = nextDueDate(
          today: today.subtract(const Duration(days: overdueWindowDays)),
          dueDay: b.dueDay,
          recurrence: b.recurrence,
          anchorMonth: b.anchorMonth);
      final createdMonth = parseMonthKey(b.anchorMonth);
      if (overdue.isBefore(startOfDay(today)) &&
          !overdue.isBefore(createdMonth) &&
          !await _isPaid(b.id, overdue)) {
        out.add(BillDue(bill: b, dueDate: overdue, isPaid: false));
        continue;
      }
      var due = nextDueDate(
          today: today,
          dueDay: b.dueDay,
          recurrence: b.recurrence,
          anchorMonth: b.anchorMonth);
      if (await _isPaid(b.id, due)) {
        due = nextDueDate(
            today: due.add(const Duration(days: 1)),
            dueDay: b.dueDay,
            recurrence: b.recurrence,
            anchorMonth: b.anchorMonth);
      }
      out.add(BillDue(bill: b, dueDate: due, isPaid: await _isPaid(b.id, due)));
    }
    out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return out;
  }

  /// 首頁提醒用：進入提醒區間、還沒繳的帳單。
  Future<List<BillDue>> dueSoon() async => [
        for (final d in await upcoming())
          if (!d.isPaid &&
              (d.dueDate.isBefore(startOfDay(ctx.now())) ||
                  isBillInReminderWindow(
                      today: ctx.now(),
                      dueDate: d.dueDate,
                      remindDaysBefore: d.bill.remindDaysBefore)))
            d,
      ];

  Future<bool> _isPaid(String billId, DateTime due) async =>
      (await ctx.db.query('bill_records',
              where: 'bill_id = ? AND due_date = ?',
              whereArgs: [billId, dateKey(due)]))
          .isNotEmpty;

  /// 標記已繳。[recordTransaction] 為 true 時一鍵記一筆支出（照常掉道具、跑規則）。
  Future<RecordOutcome?> markPaid(BillDue due,
      {required int amount, bool recordTransaction = true}) async {
    if (amount <= 0) throw const UserError('金額要大於 0');
    if (await _isPaid(due.bill.id, due.dueDate)) {
      throw const UserError('這期已經繳過了');
    }
    RecordOutcome? outcome;
    if (recordTransaction) {
      outcome = await ledger.addExpense(
        category: due.bill.category,
        amount: amount,
        paymentMethodId: due.bill.paymentMethodId,
        note: due.bill.name,
      );
    }
    await ctx.db.insert('bill_records', {
      'bill_id': due.bill.id,
      'amount': amount,
      'due_date': dateKey(due.dueDate),
      'paid_at': ctx.nowMs(),
      'transaction_id': outcome?.txn.id,
    });
    return outcome;
  }
}
