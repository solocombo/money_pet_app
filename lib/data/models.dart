import '../domain/enums.dart';
import '../domain/pet_rules.dart';

/// 資料列 ↔ Dart 物件。只放資料，不放邏輯。
DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int);
DateTime? _msOrNull(Object? v) => v == null ? null : _ms(v);
bool _b(Object? v) => v == 1;

class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.type,
    required this.stats,
    required this.lastTickDate,
    required this.createdAt,
    this.stage = 0,
    this.evolvedAt,
  });

  final String id;
  final String name;
  final PetType type;
  final PetStats stats;
  final String lastTickDate;
  final DateTime createdAt;

  /// 0 = 基本形態，1 = 進化後。
  final int stage;
  final DateTime? evolvedAt;

  bool get isEvolved => stage > 0;

  factory Pet.fromRow(Map<String, Object?> r) {
    final type = enumByName(PetType.values, r['type'] as String, PetType.cat);
    return Pet(
      id: r['id'] as String,
      name: r['name'] as String,
      type: type,
      createdAt: _ms(r['created_at']),
      stage: (r['stage'] as int?) ?? 0,
      evolvedAt: _msOrNull(r['evolved_at']),
      lastTickDate: r['last_tick_date'] as String,
      stats: PetStats(
        fullness: (r['fullness'] as num).toDouble(),
        health: (r['health'] as num).toDouble(),
        cleanliness: (r['cleanliness'] as num).toDouble(),
        mood: (r['mood'] as num).toDouble(),
        wisdom: (r['wisdom'] as num).toDouble(),
        san: (r['san'] as num).toDouble(),
        baseSan: r['base_san'] as int,
        isInsane: _b(r['is_insane']),
        insaneStreak: r['insane_streak'] as int,
      ),
    );
  }
}

Map<String, Object?> statsToRow(PetStats s) => {
      'fullness': s.fullness,
      'health': s.health,
      'cleanliness': s.cleanliness,
      'mood': s.mood,
      'wisdom': s.wisdom,
      'san': s.san,
      'is_insane': s.isInsane ? 1 : 0,
      'insane_streak': s.insaneStreak,
    };

class PetCondition {
  const PetCondition({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.expiresAt,
    this.sourceGroup,
  });

  final int id;
  final ConditionType type;
  final DateTime startedAt;
  final DateTime expiresAt;
  final CategoryGroup? sourceGroup;

  factory PetCondition.fromRow(Map<String, Object?> r) => PetCondition(
        id: r['id'] as int,
        type: enumByName(ConditionType.values, r['condition_type'] as String,
            ConditionType.fatigue),
        startedAt: _ms(r['started_at']),
        expiresAt: _ms(r['expires_at']),
        sourceGroup: r['source_group'] == null
            ? null
            : enumByName(CategoryGroup.values, r['source_group'] as String,
                CategoryGroup.other),
      );
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
    this.creditLimit,
    this.billingDay,
    this.dueDay,
  });

  final String id;
  final String name;
  final PaymentType type;
  final int? creditLimit;
  final int? billingDay;
  final int? dueDay;

  bool get isCreditCard => type == PaymentType.creditCard;

  factory PaymentMethod.fromRow(Map<String, Object?> r) => PaymentMethod(
        id: r['id'] as String,
        name: r['name'] as String,
        type: enumByName(
            PaymentType.values, r['type'] as String, PaymentType.other),
        creditLimit: r['credit_limit'] as int?,
        billingDay: r['billing_day'] as int?,
        dueDay: r['due_day'] as int?,
      );
}

class Txn {
  const Txn({
    required this.id,
    required this.type,
    required this.categoryName,
    required this.amount,
    required this.savedAmount,
    required this.occurredAt,
    this.paymentMethodId,
    this.note,
    this.droppedItemId,
    this.ptAwardedDeci = 0,
  });

  final String id;
  final TransactionType type;

  /// 支出為 [Category.name]，收入為 [IncomeCategory.name]。
  final String categoryName;
  final int amount;
  final int savedAmount;
  final DateTime occurredAt;
  final String? paymentMethodId;
  final String? note;
  final String? droppedItemId;
  final int ptAwardedDeci;

  bool get isExpense => type == TransactionType.expense;
  Category? get category => isExpense ? Category.tryParse(categoryName) : null;
  IncomeCategory? get incomeCategory => isExpense
      ? null
      : enumByName(IncomeCategory.values, categoryName, IncomeCategory.otherIncome);

  String get categoryLabel =>
      category?.label ?? incomeCategory?.label ?? categoryName;
  String get categoryEmoji => category?.emoji ?? incomeCategory?.emoji ?? '💸';

  factory Txn.fromRow(Map<String, Object?> r) => Txn(
        id: r['id'] as String,
        type: enumByName(TransactionType.values, r['type'] as String,
            TransactionType.expense),
        categoryName: r['category'] as String,
        amount: r['amount'] as int,
        savedAmount: r['saved_amount'] as int,
        occurredAt: _ms(r['occurred_at']),
        paymentMethodId: r['payment_method_id'] as String?,
        note: r['note'] as String?,
        droppedItemId: r['dropped_item_id'] as String?,
        ptAwardedDeci: r['pt_awarded'] as int,
      );
}

class Reward {
  const Reward({
    required this.id,
    required this.name,
    required this.ptCostDeci,
    required this.isRedeemed,
    this.redeemedAt,
  });

  final String id;
  final String name;
  final int ptCostDeci;
  final bool isRedeemed;
  final DateTime? redeemedAt;

  factory Reward.fromRow(Map<String, Object?> r) => Reward(
        id: r['id'] as String,
        name: r['name'] as String,
        ptCostDeci: r['pt_cost'] as int,
        isRedeemed: _b(r['is_redeemed']),
        redeemedAt: _msOrNull(r['redeemed_at']),
      );
}

class FinancialGoal {
  const FinancialGoal({
    required this.id,
    required this.name,
    required this.ptRewardDeci,
    required this.deadline,
    required this.isCompleted,
    this.description,
    this.completedAt,
  });

  final String id;
  final String name;
  final String? description;
  final int ptRewardDeci;

  /// 'yyyy-MM-dd'
  final String deadline;
  final bool isCompleted;
  final DateTime? completedAt;

  factory FinancialGoal.fromRow(Map<String, Object?> r) => FinancialGoal(
        id: r['id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        ptRewardDeci: r['pt_reward'] as int,
        deadline: r['deadline'] as String,
        isCompleted: _b(r['is_completed']),
        completedAt: _msOrNull(r['completed_at']),
      );
}

class AssetAccount {
  const AssetAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.lastUpdated,
    this.stocks = const [],
  });

  final String id;
  final String name;
  final AssetType type;

  /// 銀行 / 現金：餘額。證券：交割戶現金（股票市值另計）。
  final int balance;
  final DateTime? lastUpdated;
  final List<AssetStock> stocks;

  double get stockValue => stocks.fold(0, (s, x) => s + x.marketValue);
  double get total => balance + stockValue;

  AssetAccount withStocks(List<AssetStock> s) => AssetAccount(
        id: id,
        name: name,
        type: type,
        balance: balance,
        lastUpdated: lastUpdated,
        stocks: s,
      );

  factory AssetAccount.fromRow(Map<String, Object?> r) => AssetAccount(
        id: r['id'] as String,
        name: r['name'] as String,
        type: enumByName(AssetType.values, r['type'] as String, AssetType.other),
        balance: r['balance'] as int,
        lastUpdated: _msOrNull(r['last_updated']),
      );
}

class AssetStock {
  const AssetStock({
    required this.id,
    required this.accountId,
    required this.name,
    required this.quantity,
    required this.price,
    this.code,
  });

  final String id;
  final String accountId;
  final String name;
  final String? code;
  final double quantity;
  final double price;

  double get marketValue => quantity * price;

  factory AssetStock.fromRow(Map<String, Object?> r) => AssetStock(
        id: r['id'] as String,
        accountId: r['account_id'] as String,
        name: r['stock_name'] as String,
        code: r['stock_code'] as String?,
        quantity: (r['quantity'] as num).toDouble(),
        price: (r['current_price'] as num).toDouble(),
      );
}

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.type,
    required this.dueDay,
    required this.remindDaysBefore,
    required this.recurrence,
    required this.anchorMonth,
    required this.categoryName,
    required this.isActive,
    this.amount,
    this.paymentMethodId,
  });

  final String id;
  final String name;
  final BillType type;
  final int? amount;
  final int dueDay;
  final int remindDaysBefore;
  final Recurrence recurrence;
  final String anchorMonth;
  final String categoryName;
  final String? paymentMethodId;
  final bool isActive;

  Category get category => Category.tryParse(categoryName) ?? Category.misc;

  factory Bill.fromRow(Map<String, Object?> r) => Bill(
        id: r['id'] as String,
        name: r['name'] as String,
        type: enumByName(BillType.values, r['type'] as String, BillType.other),
        amount: r['amount'] as int?,
        dueDay: r['due_day'] as int,
        remindDaysBefore: r['remind_days_before'] as int,
        recurrence: enumByName(
            Recurrence.values, r['recurrence'] as String, Recurrence.monthly),
        anchorMonth: r['anchor_month'] as String,
        categoryName: r['category'] as String,
        paymentMethodId: r['payment_method_id'] as String?,
        isActive: _b(r['is_active']),
      );
}

/// 帳單 + 下一次到期資訊（UI 用）。
class BillDue {
  const BillDue({required this.bill, required this.dueDate, required this.isPaid});
  final Bill bill;
  final DateTime dueDate;
  final bool isPaid;
}
