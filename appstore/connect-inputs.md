# App Store Connect 入力シート(コピペ用)

App Store Connect(https://appstoreconnect.apple.com)で、上から順に入力する。
説明文・キーワード等は `metadata.md` を参照。

---

## 0. 事前準備: 有料App契約・口座・税務(サブスク販売に必須)

「ビジネス」(旧: 契約/税金/口座情報)で次を完了させる。**未完了だとサブスクを販売できない**。

- [ ] 有料App契約(Paid Apps Agreement)に同意
- [ ] 銀行口座を登録
- [ ] 税務情報: 米国税務フォーム(日本在住の個人は W-8BEN。日米租税条約で源泉税を軽減)

※有効になるまで数日かかることがあるので、最初に済ませる。

## 1. 新規App

| 欄 | 入力 |
|---|---|
| プラットフォーム | iOS |
| 名前 | `あしあと - 行った場所を記録する旅の地図` |
| プライマリ言語 | 日本語 |
| バンドルID | `com.tk634.Ashiato` |
| SKU | `ashiato-ios` |
| ユーザアクセス | アクセス制限なし |

## 2. Appの情報

| 欄 | 入力 |
|---|---|
| サブタイトル | `恋人・家族と共有、制県レベルと実績で旅がたのしい` |
| カテゴリ(プライマリ) | 旅行 |
| カテゴリ(セカンダリ) | ライフスタイル |
| コンテンツ配信権 | 第三者のコンテンツを含まない |
| 年齢制限 | 質問にはすべて「なし/いいえ」→ 4+ |

## 3. 価格および配信状況

- 価格: **無料**(アプリ内課金でサブスク)
- 配信国: すべて(または日本のみ)

## 4. Appのプライバシー

| 欄 | 入力 |
|---|---|
| プライバシーポリシーURL | `https://tk634.github.io/memory-map/privacy.html` |
| データの収集 | **「いいえ、このAppからデータを収集しません」** |

根拠: 記録はすべて利用者のiCloud(CloudKit)に保存され、開発者のサーバーは無い。解析・広告・トラッキングもなし(PrivacyInfo.xcprivacy と一致)。

## 5. サブスクリプション

| 欄 | 入力 |
|---|---|
| サブスクリプショングループ名 | `あしあとプレミアム` |
| 参照名 | `Premium Monthly` |
| 製品ID | `ashiato.premium.monthly`(コードと完全一致させる) |
| 期間 | 1か月 |
| 価格 | ¥300 |
| 導入オファー | 無料トライアル 1週間(新規ユーザー) |
| 表示名(日本語) | `プレミアム(月額)` |
| 説明(日本語) | `写真を無制限に、動画も残せる。招待した人も使えます。` |
| 審査用スクリーンショット | `~/Desktop/あしあと_ストア画像/review_paywall.png`(ペイウォール画面) |

※サブスクは**アプリのバージョン1.0と一緒に審査に出す**(バージョンページの「App内課金とサブスクリプション」で選択)。

## 6. バージョン 1.0

| 欄 | 入力 |
|---|---|
| スクリーンショット(6.9インチ) | `~/Desktop/あしあと_ストア画像/` の 1〜5 を順に |
| プロモーションテキスト | metadata.md 参照 |
| 説明 | metadata.md 参照。末尾に下記の規約行を追加 |
| キーワード | metadata.md 参照 |
| サポートURL | `https://tk634.github.io/memory-map/` |
| マーケティングURL | (空欄でよい) |
| 著作権 | `© 2026 Takahiro Sueoka` |

説明文の末尾に追加(サブスクの審査で求められる):

```
利用規約: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
プライバシーポリシー: https://tk634.github.io/memory-map/privacy.html
```

### App Reviewに関する情報

- サインイン情報: **不要**(「サインインが必要」のチェックを外す)
- 連絡先: 氏名・電話番号・メール(`taka634.official@gmail.com`)
- メモ(英語):

```
Ashiato lets users record places they have visited on a map and calendar,
and share the record with a partner or family via iCloud (CloudKit sharing).

- No account or sign-in is required. All data is stored in the user's own iCloud;
  we do not operate any server and do not collect data.
- To test sharing, tap the person (+) button at the top right to create an
  iCloud invitation link. Sharing requires two Apple IDs signed in to iCloud.
- Premium (auto-renewable subscription, 1 month, 1-week free trial) unlocks
  unlimited photos per place (free: 3 per place) and short videos.
  The subscriber's premium also applies to members they invite (up to 6 people).
  Open it from the "..." menu > プレミアム. "Restore Purchases" is on the same screen.
```

## 7. CloudKit スキーマを本番へ(提出前に必ず)

CloudKit Console(https://icloud.developer.apple.com)→ コンテナ `iCloud.com.tk634.Ashiato`
→ Schema → **Deploy Schema Changes...** → Production へ。
忘れると配信版で同期されない。**本番反映後は項目の追加のみ可能(削除・改名不可)**。

## 8. ビルドのアップロード

Xcode → Product → Archive → Distribute App → App Store Connect → Upload。
処理完了後(10〜30分)、バージョン1.0の「ビルド」欄で選択して審査へ提出。

---

## アップデートのとき

1. Xcode でバージョン(MARKETING_VERSION)を上げ、ビルド番号(CURRENT_PROJECT_VERSION)も+1
2. App Store Connect で「+バージョン」→ 変更点(このバージョンの新機能)を記入
3. Archive → Upload → ビルドを選んで審査へ
- プロモーションテキストは審査なしでいつでも変更可
- CloudKit の項目を追加したら、再び本番へ Deploy してから提出
