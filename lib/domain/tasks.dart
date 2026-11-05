enum TaskKind {
  newbie('新手任務'),
  daily('每日任務'),
  fixed('固定任務'),
  milestone('里程碑');

  const TaskKind(this.label);
  final String label;
}

/// 任務獎勵只給金幣或道具，**不給 PT**（PT 只來自省錢與財務目標）。
class TaskDef {
  const TaskDef({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.rewardCoins,
    this.rewardItemId,
  });

  /// 穩定 id，存進資料庫，**不可更改**。
  final String id;
  final TaskKind kind;
  final String name;
  final String description;
  final int rewardCoins;
  final String? rewardItemId;
}

abstract final class TaskIds {
  static const createPet = 'newbie_create_pet';
  static const firstReward = 'newbie_first_reward';
  static const firstTransaction = 'newbie_first_transaction';
  static const record7Days = 'newbie_record_7_days';
  static const firstShop = 'newbie_first_shop';
  static const firstGoal = 'newbie_first_goal';
  static const dailyCheckIn = 'daily_check_in';
  static const dailyPoke = 'daily_poke';
  static const dailyRecord = 'daily_record';
  static const assetUpdate = 'fixed_asset_update';
  static const firstCraft = 'newbie_first_craft';
  static const streak7 = 'milestone_streak_7';
  static const streak30 = 'milestone_streak_30';
  static const records100 = 'milestone_records_100';
  static const firstRedeem = 'milestone_first_redeem';
}

const int assetUpdateIntervalDays = 3;

const List<TaskDef> taskCatalog = [
  TaskDef(
    id: TaskIds.createPet,
    kind: TaskKind.newbie,
    name: '建立寵物',
    description: '迎接你的第一隻寵物',
    rewardCoins: 50,
  ),
  TaskDef(
    id: TaskIds.firstReward,
    kind: TaskKind.newbie,
    name: '設定第一個獎勵',
    description: '在獎勵櫃放一個想要的現實獎勵',
    rewardCoins: 50,
  ),
  TaskDef(
    id: TaskIds.firstTransaction,
    kind: TaskKind.newbie,
    name: '記第一筆帳',
    description: '開始記帳的第一步',
    rewardCoins: 50,
    rewardItemId: 'cocoa',
  ),
  TaskDef(
    id: TaskIds.record7Days,
    kind: TaskKind.newbie,
    name: '累計記帳 7 天',
    description: '有 7 天記過帳或按過本日無支出',
    rewardCoins: 150,
    rewardItemId: 'cold_medicine',
  ),
  TaskDef(
    id: TaskIds.firstShop,
    kind: TaskKind.newbie,
    name: '第一次逛商店',
    description: '在商店買一樣東西',
    rewardCoins: 50,
  ),
  TaskDef(
    id: TaskIds.firstCraft,
    kind: TaskKind.newbie,
    name: '第一次使用合成',
    description: '在背包把食材合成成品',
    rewardCoins: 50,
  ),
  TaskDef(
    id: TaskIds.firstGoal,
    kind: TaskKind.newbie,
    name: '建立第一個財務目標',
    description: '幫自己定一個省錢小目標',
    rewardCoins: 50,
  ),
  TaskDef(
    id: TaskIds.dailyCheckIn,
    kind: TaskKind.daily,
    name: '每日簽到',
    description: '打開 APP 看看寵物',
    rewardCoins: 20,
  ),
  TaskDef(
    id: TaskIds.dailyPoke,
    kind: TaskKind.daily,
    name: '戳戳寵物',
    description: '跟寵物互動一下',
    rewardCoins: 5,
  ),
  TaskDef(
    id: TaskIds.dailyRecord,
    kind: TaskKind.daily,
    name: '今日記帳',
    description: '記至少一筆帳，或按「本日無支出」',
    rewardCoins: 10,
  ),
  TaskDef(
    id: TaskIds.assetUpdate,
    kind: TaskKind.fixed,
    name: '更新資產資訊',
    description: '每 $assetUpdateIntervalDays 天更新一次資產帳戶餘額',
    rewardCoins: 30,
  ),
  TaskDef(
    id: TaskIds.streak7,
    kind: TaskKind.milestone,
    name: '連續記帳 7 天',
    description: '連續 7 天記帳或按本日無支出',
    rewardCoins: 200,
    rewardItemId: 'lavender_tea',
  ),
  TaskDef(
    id: TaskIds.streak30,
    kind: TaskKind.milestone,
    name: '連續記帳 30 天',
    description: '一整個月都沒有中斷！',
    rewardCoins: 1000,
    rewardItemId: 'elder_charm',
  ),
  TaskDef(
    id: TaskIds.records100,
    kind: TaskKind.milestone,
    name: '累計記帳 100 筆',
    description: '記帳老手',
    rewardCoins: 500,
    rewardItemId: 'golden_shrimp',
  ),
  TaskDef(
    id: TaskIds.firstRedeem,
    kind: TaskKind.milestone,
    name: '第一次兌換獎勵',
    description: '用 PT 兌換獎勵櫃裡的獎勵',
    rewardCoins: 100,
    rewardItemId: 'star_projector',
  ),
];

TaskDef taskById(String id) => taskCatalog.firstWhere((t) => t.id == id);

/// 本日無支出的額外金幣獎勵。
const int noSpendCoinReward = 10;
