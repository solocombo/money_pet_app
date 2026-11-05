import 'package:sqflite_common/sqlite_api.dart';

/// 資料庫 schema。
///
/// 慣例：
/// - 時間點用毫秒 epoch（INTEGER），日期用 'yyyy-MM-dd'，月份用 'yyyy-MM'。
/// - 金額為整數（TWD 元）。
/// - PT 一律存 deci-PT 整數（1 = 0.1 PT）。
/// - 金幣、PT 餘額**由 log 加總而來**，log 是唯一真相來源。
/// - enum 以 name 字串儲存。
///
/// 改 schema 時：把 [schemaVersion] +1，並在 [_migrations] 加上對應步驟。
const int schemaVersion = 1;

const String databaseFileName = 'money_pet.db';

Future<void> onCreateDatabase(Database db, int version) async {
  final batch = db.batch();
  for (final sql in _v1) {
    batch.execute(sql);
  }
  await batch.commit(noResult: true);
  // 之後版本的 migration 依序套用，確保新安裝與升級的結果一致。
  for (var v = 2; v <= version; v++) {
    await _migrations[v]!(db);
  }
}

Future<void> onUpgradeDatabase(Database db, int oldVersion, int newVersion) async {
  for (var v = oldVersion + 1; v <= newVersion; v++) {
    await _migrations[v]!(db);
  }
}

Future<void> onConfigureDatabase(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

final Map<int, Future<void> Function(Database)> _migrations = {};

/// 清除所有資料時要清空的表（依外鍵相依順序，子表在前）。
const List<String> allTables = [
  'bill_records',
  'bills',
  'asset_log',
  'asset_stocks',
  'asset_accounts',
  'shop_purchases',
  'task_progress',
  'financial_goals',
  'rewards',
  'pt_log',
  'coin_log',
  'item_collection',
  'inventory',
  'month_settlements',
  'budget_results',
  'budgets',
  'no_spend_days',
  'transactions',
  'payment_methods',
  'pet_conditions',
  'pet_status',
  'pets',
  'app_settings',
];

const List<String> _v1 = [
  '''
  CREATE TABLE app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )''',
  '''
  CREATE TABLE pets (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL,
    base_san   INTEGER NOT NULL,
    is_active  INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE pet_status (
    pet_id         TEXT PRIMARY KEY REFERENCES pets(id) ON DELETE CASCADE,
    fullness       REAL NOT NULL,
    health         REAL NOT NULL,
    cleanliness    REAL NOT NULL,
    mood           REAL NOT NULL,
    wisdom         REAL NOT NULL,
    san            REAL NOT NULL,
    is_insane      INTEGER NOT NULL DEFAULT 0,
    insane_streak  INTEGER NOT NULL DEFAULT 0,
    last_tick_date TEXT NOT NULL,
    last_updated   INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE pet_conditions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id          TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    condition_type  TEXT NOT NULL,
    source_group    TEXT,
    source_month    TEXT,
    started_at      INTEGER NOT NULL,
    expires_at      INTEGER NOT NULL,
    is_cured        INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE payment_methods (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    type         TEXT NOT NULL,
    credit_limit INTEGER,
    billing_day  INTEGER,
    due_day      INTEGER,
    is_archived  INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE transactions (
    id                TEXT PRIMARY KEY,
    type              TEXT NOT NULL,
    category          TEXT NOT NULL,
    amount            INTEGER NOT NULL CHECK (amount > 0),
    saved_amount      INTEGER NOT NULL DEFAULT 0
                      CHECK (saved_amount >= 0 AND saved_amount <= amount),
    payment_method_id TEXT REFERENCES payment_methods(id) ON DELETE SET NULL,
    note              TEXT,
    occurred_at       INTEGER NOT NULL,
    created_at        INTEGER NOT NULL,
    pt_awarded        INTEGER NOT NULL DEFAULT 0,
    dropped_item_id   TEXT
  )''',
  'CREATE INDEX idx_transactions_occurred ON transactions(occurred_at)',
  '''
  CREATE TABLE no_spend_days (
    date       TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE budgets (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    month      TEXT NOT NULL,
    grp        TEXT NOT NULL,   -- CategoryGroup.name，'total' 代表總額預算
    amount     INTEGER NOT NULL CHECK (amount > 0),
    UNIQUE (month, grp)
  )''',
  '''
  CREATE TABLE budget_results (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    month         TEXT NOT NULL,
    grp           TEXT NOT NULL,
    budget_amount INTEGER NOT NULL,
    actual_amount INTEGER NOT NULL,
    pt_earned     INTEGER NOT NULL,
    is_overspent  INTEGER NOT NULL,
    created_at    INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE month_settlements (
    month         TEXT PRIMARY KEY,
    no_pt_penalty INTEGER NOT NULL,
    gross_pt      INTEGER NOT NULL,
    awarded_pt    INTEGER NOT NULL,
    settled_at    INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE inventory (
    item_id  TEXT PRIMARY KEY,
    quantity INTEGER NOT NULL CHECK (quantity >= 0)
  )''',
  '''
  CREATE TABLE item_collection (
    item_id           TEXT PRIMARY KEY,
    first_obtained_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE coin_log (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    source     TEXT NOT NULL,
    amount     INTEGER NOT NULL,
    note       TEXT,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE pt_log (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    source     TEXT NOT NULL,
    amount     INTEGER NOT NULL,  -- deci-PT
    period     TEXT NOT NULL,     -- 算進哪個月的上限（yyyy-MM）
    note       TEXT,
    ref_id     TEXT,
    created_at INTEGER NOT NULL
  )''',
  'CREATE INDEX idx_pt_log_period ON pt_log(period)',
  '''
  CREATE TABLE rewards (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    pt_cost     INTEGER NOT NULL CHECK (pt_cost > 0),
    is_redeemed INTEGER NOT NULL DEFAULT 0,
    redeemed_at INTEGER,
    created_at  INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE financial_goals (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    description  TEXT,
    pt_reward    INTEGER NOT NULL CHECK (pt_reward >= 0),
    deadline     TEXT NOT NULL,
    is_completed INTEGER NOT NULL DEFAULT 0,
    completed_at INTEGER,
    created_at   INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE task_progress (
    task_id      TEXT NOT NULL,
    period       TEXT NOT NULL,   -- 一次性任務為 ''，每日任務為日期
    completed_at INTEGER NOT NULL,
    claimed_at   INTEGER,
    PRIMARY KEY (task_id, period)
  )''',
  '''
  CREATE TABLE shop_purchases (
    date         TEXT NOT NULL,
    slot         INTEGER NOT NULL,
    item_id      TEXT NOT NULL,
    price        INTEGER NOT NULL,
    purchased_at INTEGER NOT NULL,
    PRIMARY KEY (date, slot)
  )''',
  '''
  CREATE TABLE asset_accounts (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    type         TEXT NOT NULL,
    balance      INTEGER NOT NULL DEFAULT 0,
    last_updated INTEGER,
    created_at   INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE asset_stocks (
    id            TEXT PRIMARY KEY,
    account_id    TEXT NOT NULL REFERENCES asset_accounts(id) ON DELETE CASCADE,
    stock_name    TEXT NOT NULL,
    stock_code    TEXT,
    quantity      REAL NOT NULL,
    current_price REAL NOT NULL,
    last_updated  INTEGER NOT NULL,
    created_at    INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE asset_log (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id       TEXT NOT NULL REFERENCES asset_accounts(id) ON DELETE CASCADE,
    balance_snapshot INTEGER NOT NULL,
    recorded_at      INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE bills (
    id                 TEXT PRIMARY KEY,
    name               TEXT NOT NULL,
    type               TEXT NOT NULL,
    amount             INTEGER,
    due_day            INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 31),
    remind_days_before INTEGER NOT NULL DEFAULT 3,
    recurrence         TEXT NOT NULL,
    anchor_month       TEXT NOT NULL,
    category           TEXT NOT NULL DEFAULT 'misc',
    payment_method_id  TEXT REFERENCES payment_methods(id) ON DELETE SET NULL,
    is_active          INTEGER NOT NULL DEFAULT 1,
    created_at         INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE bill_records (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    bill_id        TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    amount         INTEGER NOT NULL,
    due_date       TEXT NOT NULL,
    paid_at        INTEGER NOT NULL,
    transaction_id TEXT REFERENCES transactions(id) ON DELETE SET NULL,
    UNIQUE (bill_id, due_date)
  )''',
];
