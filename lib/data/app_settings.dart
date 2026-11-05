import 'dart:convert';

import '../domain/pt_rules.dart';

/// 使用者設定。整份存成一個 JSON，放在 app_settings 表的 'settings' 欄。
/// 新增欄位時記得給預設值，舊資料讀進來才不會壞。
class AppSettings {
  const AppSettings({
    this.onboardingDone = false,
    this.overspendThreshold = 0.2,
    this.creditWarnRatio = 0.8,
    this.weekStartsMonday = true,
    this.currency = 'TWD',
    this.ptRates = const PtRates(),
    this.easyMode = false,
    this.disableGarble = false,
    this.disableSanCheck = false,
    this.impulseThreshold = 3000,
    this.repeatCategoryThreshold = 3,
    this.dailyDropLimit = 10,
    this.dailyReminderTime = '21:00',
    this.billRemindDaysDefault = 3,
    this.receiveBroadcast = true,
    this.notificationsEnabled = true,
    this.dailyReminderEnabled = true,
  });

  final bool onboardingDone;

  // 財務設定
  final double overspendThreshold;
  final double creditWarnRatio;
  final bool weekStartsMonday;
  final String currency;
  final PtRates ptRates;

  // 寵物設定
  final bool easyMode;
  final bool disableGarble;
  final bool disableSanCheck;

  /// 單筆支出超過這個金額會觸發 San check（衝動消費）。
  final int impulseThreshold;

  /// 同類別當天超過幾筆會觸發 San check。
  final int repeatCategoryThreshold;

  /// 每天最多掉落幾個道具（防止新增 / 刪除刷道具）。
  final int dailyDropLimit;

  // 通知設定
  final String dailyReminderTime;
  final int billRemindDaysDefault;
  final bool receiveBroadcast;

  /// 本地通知總開關。
  final bool notificationsEnabled;
  final bool dailyReminderEnabled;

  AppSettings copyWith({
    bool? onboardingDone,
    double? overspendThreshold,
    double? creditWarnRatio,
    bool? weekStartsMonday,
    String? currency,
    PtRates? ptRates,
    bool? easyMode,
    bool? disableGarble,
    bool? disableSanCheck,
    int? impulseThreshold,
    int? repeatCategoryThreshold,
    int? dailyDropLimit,
    String? dailyReminderTime,
    int? billRemindDaysDefault,
    bool? receiveBroadcast,
    bool? notificationsEnabled,
    bool? dailyReminderEnabled,
  }) =>
      AppSettings(
        onboardingDone: onboardingDone ?? this.onboardingDone,
        overspendThreshold: overspendThreshold ?? this.overspendThreshold,
        creditWarnRatio: creditWarnRatio ?? this.creditWarnRatio,
        weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
        currency: currency ?? this.currency,
        ptRates: ptRates ?? this.ptRates,
        easyMode: easyMode ?? this.easyMode,
        disableGarble: disableGarble ?? this.disableGarble,
        disableSanCheck: disableSanCheck ?? this.disableSanCheck,
        impulseThreshold: impulseThreshold ?? this.impulseThreshold,
        repeatCategoryThreshold:
            repeatCategoryThreshold ?? this.repeatCategoryThreshold,
        dailyDropLimit: dailyDropLimit ?? this.dailyDropLimit,
        dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
        billRemindDaysDefault:
            billRemindDaysDefault ?? this.billRemindDaysDefault,
        receiveBroadcast: receiveBroadcast ?? this.receiveBroadcast,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      );

  Map<String, Object?> toJson() => {
        'onboardingDone': onboardingDone,
        'overspendThreshold': overspendThreshold,
        'creditWarnRatio': creditWarnRatio,
        'weekStartsMonday': weekStartsMonday,
        'currency': currency,
        'pt': {
          'categorySaving': ptRates.categorySaving,
          'totalSaving': ptRates.totalSaving,
          'income': ptRates.income,
          'savedAmount': ptRates.savedAmount,
          'monthlyCapDeci': ptRates.monthlyCapDeci,
        },
        'easyMode': easyMode,
        'disableGarble': disableGarble,
        'disableSanCheck': disableSanCheck,
        'impulseThreshold': impulseThreshold,
        'repeatCategoryThreshold': repeatCategoryThreshold,
        'dailyDropLimit': dailyDropLimit,
        'dailyReminderTime': dailyReminderTime,
        'billRemindDaysDefault': billRemindDaysDefault,
        'receiveBroadcast': receiveBroadcast,
        'notificationsEnabled': notificationsEnabled,
        'dailyReminderEnabled': dailyReminderEnabled,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) {
    const d = AppSettings();
    T v<T>(String k, T fallback) {
      final x = j[k];
      if (x is T) return x;
      if (fallback is double && x is num) return x.toDouble() as T;
      return fallback;
    }

    final pt = (j['pt'] as Map?)?.cast<String, Object?>() ?? const {};
    double r(String k, double fb) => (pt[k] as num?)?.toDouble() ?? fb;
    return AppSettings(
      onboardingDone: v('onboardingDone', d.onboardingDone),
      overspendThreshold: v('overspendThreshold', d.overspendThreshold),
      creditWarnRatio: v('creditWarnRatio', d.creditWarnRatio),
      weekStartsMonday: v('weekStartsMonday', d.weekStartsMonday),
      currency: v('currency', d.currency),
      ptRates: PtRates(
        categorySaving: r('categorySaving', d.ptRates.categorySaving),
        totalSaving: r('totalSaving', d.ptRates.totalSaving),
        income: r('income', d.ptRates.income),
        savedAmount: r('savedAmount', d.ptRates.savedAmount),
        monthlyCapDeci:
            (pt['monthlyCapDeci'] as num?)?.toInt() ?? d.ptRates.monthlyCapDeci,
      ),
      easyMode: v('easyMode', d.easyMode),
      disableGarble: v('disableGarble', d.disableGarble),
      disableSanCheck: v('disableSanCheck', d.disableSanCheck),
      impulseThreshold: v('impulseThreshold', d.impulseThreshold),
      repeatCategoryThreshold:
          v('repeatCategoryThreshold', d.repeatCategoryThreshold),
      dailyDropLimit: v('dailyDropLimit', d.dailyDropLimit),
      dailyReminderTime: v('dailyReminderTime', d.dailyReminderTime),
      billRemindDaysDefault: v('billRemindDaysDefault', d.billRemindDaysDefault),
      receiveBroadcast: v('receiveBroadcast', d.receiveBroadcast),
      notificationsEnabled: v('notificationsEnabled', d.notificationsEnabled),
      dailyReminderEnabled: v('dailyReminderEnabled', d.dailyReminderEnabled),
    );
  }

  String encode() => jsonEncode(toJson());

  static AppSettings decode(String? s) {
    if (s == null || s.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(
          (jsonDecode(s) as Map).cast<String, Object?>());
    } catch (_) {
      return const AppSettings();
    }
  }
}
