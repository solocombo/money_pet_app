# 錢寵（Money Pet）

記帳養寵物，省錢換獎勵。Flutter APP，資料只存在手機本地（SQLCipher 加密）。

完整企劃見 [`docs/design.md`](docs/design.md)。

| 首頁 | 記帳 | 記一筆 | 商店 |
|---|---|---|---|
| ![](docs/screenshots/01_home.png) | ![](docs/screenshots/02_ledger.png) | ![](docs/screenshots/03_add.png) | ![](docs/screenshots/04_shop.png) |
| **圖鑑** | **任務** | **獎勵櫃** | **San 值失控** |
| ![](docs/screenshots/05_collection.png) | ![](docs/screenshots/06_tasks.png) | ![](docs/screenshots/07_rewards.png) | ![](docs/screenshots/08_insane.png) |

> 截圖是在測試環境用系統字型渲染的，部分 emoji 與數字間距和實機不同。

## 開發

```bash
flutter pub get
flutter run            # 需接 Android 手機或模擬器
flutter test           # 單元 + 整合 + widget 測試
flutter analyze
```

重新產生截圖（需要 Linux 的文泉驛正黑與 Noto Color Emoji 字型）：

```bash
SCREENSHOTS=1 flutter test --update-goldens test/screenshots/
```

## 架構

```
lib/
  domain/     純 Dart 規則（無 I/O，全部有單元測試）
    pt_rules.dart       PT 計算、每月上限、月結算
    pet_rules.dart      屬性下降、San 值、生病、道具效果、San check
    items.dart          道具清單、稀有度掉落
    shop_rules.dart     每日商店（以日期為種子）
    finance_rules.dart  帳單到期日、信用卡週期與警戒
    tasks.dart          任務定義
  data/       SQLite schema、資料模型、設定、SQLCipher 開啟
  services/   業務流程（每個寫入都包在 transaction 裡）
  state/      Riverpod providers
  ui/         畫面
test/
  domain/     規則單元測試
  services/   整合測試（sqflite_common_ffi in-memory）
  widget/     完整操作流程測試
```

**資料慣例**
- 金幣與 PT 餘額**由 log 加總而來**（`coin_log`、`pt_log`），log 是唯一真相來源，不另存餘額。
- PT 一律存 **deci-PT 整數**（1 = 0.1 PT），避免浮點誤差；1 deci-PT = 1 金幣。
- 改 schema：`schemaVersion + 1`，並在 `database.dart` 的 `_migrations` 加步驟。

## 已實作（v0.1 MVP）

- 記帳：支出 / 收入、19 個子類別、支付工具、本次省下金額、補記過去日期、刪除
- 本日無支出打卡
- 寵物：六種屬性、每日自然下降（離線多天會補算）、戳戳隨機反應、智慧等級
- San 值：四種 San check 觸發、失控（亂碼 + 去飽和 + 動作凍結 + 商店暫停）、連續記帳 3 天恢復
- 生病：單一類別超支 → 對應病症，5 天自動康復或用藥
- 道具：26 種、四級稀有度掉落、背包、使用、賣出、圖鑑（剪影）
- 簡易商店：每日 4 格（含 7 折限定），每格每天限購一次
- PT：收入、省下金額、月底兩層結算（雙重獎勵、半數超支無 PT）、PT 換金幣
- 獎勵櫃、財務目標
- 任務：新手、每日（簽到 / 戳戳 / 記帳）、固定（每 3 天更新資產）
- 預算（總額 + 七大類），新月份自動沿用上月
- 資產統計（銀行 / 證券含股票 / 現金）與快照紀錄
- 帳單提醒（每月 / 季 / 年、逾期顯示、一鍵記帳）、信用卡本期額度警戒
- Onboarding（中途離開會從未完成的步驟繼續）
- 設定頁、清除所有資料（二次確認）
- SQLCipher 加密，金鑰存在 Android Keystore / iOS Keychain

## 設計決策（企劃書以外補充的規則）

| 項目 | 決定 |
|---|---|
| 省下金額 | 不能超過消費金額（UI 與資料庫 CHECK 都會擋） |
| 每月 PT 上限 | 預設 2000 PT，可在設定調整，0 = 不限。涵蓋收入、省下金額、月結算；**財務目標不受限** |
| 沒設預算 | 只拿道具，不拿任何自動 PT（財務目標仍可拿） |
| 補記過去月份 | 只拿道具，不拿 PT（避免補記舊帳刷 PT） |
| 刪除交易 | 退回該筆 PT（上限額度也回補）；道具若還在背包就收回 |
| 每日掉落上限 | 預設 10 次，用計數器而非筆數，「新增 → 用道具 → 刪除」也刷不到 |
| 記帳屬性加成 | 每筆支出對應屬性 +3，與金額無關（不鼓勵消費），和掉落共用每日上限 |
| 打卡後又記支出 | 自動取消當天的本日無支出，並收回打卡金幣 |
| 超支生病 | 記帳當下即判定；同類別同月份只觸發一次 |
| 月結算時機 | 新月份第一次開 APP 時結算上個月 |
| San check | 多個觸發條件只擲一次；失敗率 50%，每智慧等級 -5% |
| San 上限 | 初始值 + (智慧等級 − 1) × 5，最高 100（「智慧轉換 San」的暫定版） |
| 失控 | 屬性每天額外 -2；連續記帳 3 天、或理智道具讓 San 回到 40 以上即恢復 |
| 深夜記帳 | 凌晨 0:00–4:59 |
| 「第一次使用合成」新手任務 | 合成系統上線前，暫時換成「第一次逛商店」 |
| 寵物外觀 | MVP 先用 emoji，之後換 itch.io 像素素材 |

## 還沒做（下一步）

- **本地推播通知**（`flutter_local_notifications`）：帳單、每日提醒、資產更新。目前提醒顯示在首頁。
- AdMob 激勵廣告換金幣
- FCM 全體推播
- Google Drive 備份 / 還原（v1.2）
- 正式簽章設定（目前 release 用 debug key）、APP icon
- 隱私權政策頁
- 合成、寵物進化、月報表等 v1.1 以後的功能
