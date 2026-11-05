/// 遊戲與記帳共用的列舉定義。
///
/// 所有 enum 都用 [name] 存進資料庫，所以**不要重新命名既有的值**，
/// 否則舊資料會讀不回來。新增值則沒問題。
library;

/// 寵物的六種屬性。
enum PetAttribute {
  fullness('飽食'),
  health('健康'),
  cleanliness('整潔'),
  mood('心情'),
  wisdom('智慧'),
  san('理智');

  const PetAttribute(this.label);
  final String label;

  /// 會自然下降、而且會被「任一屬性低於 30」檢查的四種屬性。
  static const decaying = [fullness, health, cleanliness, mood];
}

/// 寵物種類（MVP 只開放基本款）。
enum PetType {
  cat('貓', '🐱', 80, '高冷，天生淡定'),
  dog('狗', '🐶', 60, '熱情，容易受刺激'),
  fox('狐狸', '🦊', 70, '聰明，中等穩定'),
  bird('鳥', '🐦', 50, '敏感，最容易失控');

  const PetType(this.label, this.emoji, this.baseSan, this.description);
  final String label;
  final String emoji;
  final int baseSan;
  final String description;
}

/// 生病狀態，對應設計文件第六章。
enum ConditionType {
  gastroenteritis('腸胃炎', '道具效果減半'),
  medicineDependence('藥物依賴', '健康值上限降為 70'),
  shopaholic('購物狂', '整潔道具不升反降'),
  overindulgence('過度放縱', '心情值下降速度加倍'),
  fatigue('通用疲勞', '所有屬性下降速度 ×1.5');

  const ConditionType(this.label, this.effect);
  final String label;
  final String effect;
}

/// 消費主類別。
enum CategoryGroup {
  food('飲食類', PetAttribute.fullness, ConditionType.gastroenteritis),
  health('健康類', PetAttribute.health, ConditionType.medicineDependence),
  living('生活類', PetAttribute.cleanliness, ConditionType.shopaholic),
  entertainment('娛樂類', PetAttribute.mood, ConditionType.overindulgence),
  learning('學習類', PetAttribute.wisdom, ConditionType.fatigue),
  transport('交通類', null, ConditionType.fatigue),
  other('其他', PetAttribute.mood, ConditionType.fatigue);

  const CategoryGroup(this.label, this.attribute, this.condition);
  final String label;

  /// 記這類帳時會小幅提升的屬性；null 代表沒有直接效果。
  final PetAttribute? attribute;

  /// 這類超支時觸發的生病狀態。
  final ConditionType condition;
}

/// 消費子類別（實際記帳時選的類別）。
enum Category {
  dining('餐飲外食', CategoryGroup.food, '🍜'),
  groceries('食材採買', CategoryGroup.food, '🥬'),
  drinks('飲料咖啡', CategoryGroup.food, '🧋'),
  medical('醫療保健', CategoryGroup.health, '🏥'),
  fitness('運動健身', CategoryGroup.health, '🏋️'),
  supplements('藥物補給品', CategoryGroup.health, '💊'),
  clothing('治裝服飾', CategoryGroup.living, '👕'),
  dailyGoods('日用品', CategoryGroup.living, '🧻'),
  home('居家用品', CategoryGroup.living, '🛋️'),
  leisure('休閒娛樂', CategoryGroup.entertainment, '🎮'),
  subscription('訂閱服務', CategoryGroup.entertainment, '📺'),
  travel('旅遊', CategoryGroup.entertainment, '✈️'),
  books('書籍', CategoryGroup.learning, '📚'),
  courses('課程／學習', CategoryGroup.learning, '🎓'),
  publicTransport('大眾運輸', CategoryGroup.transport, '🚇'),
  fuelParking('油錢／停車', CategoryGroup.transport, '⛽'),
  gifts('人情禮金', CategoryGroup.other, '🧧'),
  donation('捐款', CategoryGroup.other, '🤝'),
  misc('其他', CategoryGroup.other, '📦');

  const Category(this.label, this.group, this.emoji);
  final String label;
  final CategoryGroup group;
  final String emoji;

  static Category? tryParse(String? name) {
    if (name == null) return null;
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// 收入類別。
enum IncomeCategory {
  salary('薪資', '💼'),
  bonus('獎金', '🎁'),
  partTime('打工／兼職', '🧑‍🍳'),
  investment('投資收益', '📈'),
  allowance('零用錢', '👛'),
  otherIncome('其他收入', '💰');

  const IncomeCategory(this.label, this.emoji);
  final String label;
  final String emoji;
}

enum TransactionType { expense, income }

enum PaymentType {
  cash('現金'),
  creditCard('信用卡'),
  transfer('轉帳'),
  other('其他');

  const PaymentType(this.label);
  final String label;
}

enum Rarity {
  common('普通', 60),
  rare('稀有', 25),
  epic('史詩', 12),
  legendary('傳說', 3);

  const Rarity(this.label, this.dropWeight);
  final String label;

  /// 掉落權重（百分比），四者加總 = 100。
  final int dropWeight;
}

enum AssetType {
  bank('銀行'),
  securities('證券'),
  cash('現金'),
  other('其他');

  const AssetType(this.label);
  final String label;
}

enum BillType {
  creditCard('信用卡'),
  utilities('水電'),
  rent('房租'),
  subscription('訂閱'),
  other('其他');

  const BillType(this.label);
  final String label;
}

enum Recurrence {
  monthly('每月', 1),
  quarterly('每季', 3),
  yearly('每年', 12);

  const Recurrence(this.label, this.months);
  final String label;
  final int months;
}

T enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
