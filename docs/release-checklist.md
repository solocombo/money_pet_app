# 上架前檢查清單

程式碼裡能做的都做了，下面是**需要你本人操作**的部分。

## 1. 在手機上測試

- [ ] 到 GitHub → **Actions** → 最新一次 CI → **Artifacts** 下載 `money-pet-apk`，解壓後安裝到手機
- [ ] 跑一次完整流程：Onboarding → 記帳 → 道具 → 合成 → 商店 → 任務 → 獎勵櫃
- [ ] 確認收得到通知（可在「設定 → 通知設定」改每日提醒時間到幾分鐘後測試）
- [ ] 匯出備份 → 清除所有資料 → 從備份還原
- [ ] 找 5–10 位朋友試用（企劃第十九章）

## 2. 正式簽章（必做）

目前沒有 `key.properties`，所以 release 版用 debug key 簽，Google Play 不接受。

```bash
keytool -genkey -v -keystore ~/money-pet-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- [ ] 建立 `android/key.properties`（**不要 commit**，已在 .gitignore）：
  ```
  storePassword=你的密碼
  keyPassword=你的密碼
  keyAlias=upload
  storeFile=/絕對路徑/money-pet-upload.jks
  ```
- [ ] 建好後 `flutter build appbundle` 就會自動用正式金鑰（`build.gradle.kts` 已設定好；沒有這個檔案時會退回 debug key）
- [ ] **金鑰檔和密碼一定要備份**，弄丟就無法更新 APP

## 3. AdMob

- [ ] 到 <https://admob.google.com> 建立 APP，取得 **APP ID** 和**激勵廣告單元 ID**
- [ ] 替換三個地方的測試 ID：
  - `lib/platform/admob.dart`（廣告單元 ID）
  - `android/app/src/main/AndroidManifest.xml`（APP ID）
  - `ios/Runner/Info.plist`（APP ID）
- [ ] 開發期間**不要點自己的正式廣告**，會被停權

## 4. 隱私權政策

- [ ] 在 `docs/privacy.md` 最後填入聯絡信箱
- [ ] GitHub repo → Settings → Pages → Source 選 `main` / `docs`，就會有公開網址：
  `https://solocombo.github.io/money_pet_app/privacy`
  （repo 是 private 的話 Pages 需要付費方案；也可以把 privacy.md 貼到 Notion 公開頁）
- [ ] Play Console 填入這個網址

## 5. Google Play Console

- [ ] 註冊開發者帳號（一次性 US$25）
- [ ] 建立應用程式，套件名稱：`com.solocombo.money_pet_app`（**上架後不能改**，想換現在講）
- [ ] 「資料安全性」表單：
  - 收集的資料：**裝置或其他 ID**（AdMob 廣告 ID）→ 用途：廣告
  - 財務資料：**不收集**（只存在裝置上，不傳出）
  - 資料傳輸加密：是
  - 使用者可要求刪除資料：是（APP 內清除所有資料）
- [ ] 內容分級問卷
- [ ] 目標對象：18 歲以上（避免家庭政策審查）
- [ ] 先上「內部測試」軌道

## 6. 素材

- [ ] 正式 APP icon（目前是 emoji 暫代）
- [ ] 寵物圖（目前是 emoji，可換 itch.io 像素素材，記得確認授權可商用）
- [ ] Play 商店截圖（至少 2 張）、512×512 icon、1024×500 主視覺圖

## 之後的功能需要的設定

| 功能 | 需要你做的 |
|---|---|
| Google Drive 自動備份 | Google Cloud 專案、OAuth 同意畫面、Android OAuth client（需要簽章 SHA-1） |
| FCM 全體推播 | Firebase 專案，下載 `google-services.json` |
| 付費進階版（NT$90） | Play Console 建立「一次性購買」商品 |
