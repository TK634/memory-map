# あしあと — やることリスト

iPhoneアプリ「あしあと」をApp Storeでリリースするまでのタスク一覧。

## 現在の状況(2026-10-12)

**2026-10-12 審査を取り下げ。写真の不具合修正・旅機能・場所ごとのアルバム・複数人利用の不具合修正を入れた 1.0 (2) で出し直す。 → 同日 1.0 (2) で再提出(審査待ち)。**

出し直しの手順:
- [x] データモデル版2(Trip 追加)。実機の版1データからの移行を確認済み
- [x] 実機で -initCloudKitSchema 実行済み(開発環境に Trip 等を登録)
- [x] CloudKit Console で Deploy Schema Changes(本番へ。2026-10-12)
- [ ] 実機(iPhone 11)で写真の追加・削除、旅の作成を確認
- [x] 1.0 (2) をアップロード(2026-10-12 13:46)
- [x] バージョン1.0のビルドを (1) → (2) に差し替え
- [x] スクリーンショットを6枚に差し替え(2_trip, 3_album が新規・変更)。説明文に旅・アルバムを追記
- [x] グループ・サブスク・アプリの3点を審査に提出(2026-10-12)
- [x] 2026-10-13 Guideline 2.1 Information Needed(実績の少ない開発者向けの追加情報依頼)→ 実機録画2本+返信文(appstore/review-reply-2026-10-15.md)・メモ追記・規約(DPLA/有料アプリ)同意のうえ 2026-10-16 再提出
- [x] 2026-10-17 3.1.2(説明文にEULAリンクなし)で却下。原因は説明文が「旅」「アルバム」の2段落だけに置き換わっていたこと → 全文+サブスク詳細+EULA/プライバシーリンクに戻し、録画2本付きで返信して 2026-10-18 再提出
- [ ] 実機2台(別のApple ID)で共有テスト: 招待された側で場所・写真・ひとこと・リアクション・旅が保存・同期されるか

- [x] App Store Connect: アプリ登録(Apple ID 6821633516)・説明文・スクリーンショット5枚(6.9インチ)・連絡先
- [x] アプリ情報(旅行/ライフスタイル)・年齢制限 4+・価格 無料・配信国 日本のみ
- [x] プライバシー: データ収集なし(公開済み)。ポリシー/サポート: GitHub Pages(docs/)
- [x] サブスク ashiato.premium.monthly: ¥300/月・1週間無料(終了日なし)・猶予期間16日(有料継続者のみ)・ファミリー共有オフ
- [x] CloudKit スキーマを本番へ Deploy(事前に -initCloudKitSchema で全項目を開発環境へ登録)
- [x] ビルド 1.0 (1) をアップロードし、バージョン1.0に設定
- [x] 銀行口座・納税フォーム(W-8BEN)提出
- [x] 有料アプリ契約が「有効」に
- [x] 審査に提出(グループ・サブスク・アプリの3点を同じ提出物で。どれか欠けると「審査へ提出できません」になる)
- [ ] 次のバージョンで: iMessageアプリ欄に誤って入れたスクリーンショット5枚を削除(本体用はメディアマネージャー > iPhone > Dynamic Island中型)
- [ ] 承認後、手動でリリース(「手動でリリースする」を選択済み)
- [x] App Store Small Business Program に申請(2026-10-12。承認メール待ち。承認月の翌月から手数料15%)

入力内容と各画面への直接リンクは appstore/connect-inputs.md 。

## 進捗サマリー

- [x] Webプロトタイプ(地図ピン・メンバー・年フィルター・ランキング) → `web-prototype/`
- [x] iOSアプリ本体のコード(SwiftUI + MapKit + CloudKit) → `ios/`
- [x] iCloud共有(CKShare)実装
- [x] データモデルに写真・コメント用 Attachment エンティティ追加
- [x] サブスク課金と写真・コメント機能の実装(コード完了。App Store Connect設定は別途)
- [ ] Xcodeビルド・実機確認
- [ ] App Store 申請

## 1. 開発環境(自分でやること)

- [ ] Mac + Xcode 15以上を用意
- [ ] Apple Developer Program に登録(年99ドル)
- [ ] Xcodeで新規iOSプロジェクト作成(名前: Ashiato)し、`ios/` のファイルを差し替え
- [ ] Signing & Capabilities:
  - [ ] iCloud → CloudKit → コンテナ作成(例 `iCloud.com.あなたのID.Ashiato`)
  - [ ] `Persistence.swift` の `cloudKitContainerID` を書き換え
  - [ ] Background Modes → Remote notifications
- [ ] Target → General → Display Name を「あしあと」に設定
- [ ] 実機で起動確認(ピン追加・メンバー・フィルター・ランキング)
- [ ] Apple ID 2つで iCloud共有(招待→共同編集)の動作確認

## 2. サブスク+写真・コメント機能(実装の続き)

- [x] Core Data: `Attachment`(imageData / comment)エンティティ追加済み
- [x] `StoreManager.swift`: StoreKit 2 でサブスク購入・状態監視・復元
- [x] `PaywallView.swift`: ペイウォール画面(継続的価値の明示: 写真無制限+今後の機能追加)
- [x] `AddEditPlaceView` に写真(PhotosUI)・コメント欄を追加(コメントは無料、写真はプレミアム)
- [x] 写真は圧縮してから保存(`UIImage.compressedJPEGData` 長辺2000px / JPEG 0.7)
- [ ] App Store Connect でサブスク商品を作成
  - プロダクトID例: `ashiato.premium.monthly`
  - 価格・無料トライアル(例: 1週間)を設定
- [ ] Sandboxテスターで購入・復元・解約をテスト

## 3. App Store 申請

- [ ] App Store Connect にアプリ登録(名前: あしあと)
- [ ] CloudKit Console でスキーマを **Production にデプロイ**(忘れると製品版で同期しない)
- [ ] スクリーンショット(6.7インチ必須)・説明文・キーワード
- [ ] プライバシー表示: 収集データ「なし」(データはユーザーのiCloudのみ、開発者サーバーなし)
- [ ] 審査メモにサブスクの継続的価値(写真機能、今後のアップデート計画)を記載
- [ ] 審査提出 → リジェクト対応(あれば)

## 4. リリース後の検討事項

- [ ] Mac版(マルチプラットフォーム化。CloudKitのまま同期可)
- [ ] Web版/Android対応が必要になったら Firebase/Supabase への移行を検討
- [ ] 「片方だけ行った場所」リスト、月別グラフなどの追加機能
- [ ] 小規模事業者プログラム申請(手数料30%→15%)

## リポジトリ構成

```
├── README.md          # このプロジェクトの概要
├── TODO.md            # このファイル
├── ios/               # iOSアプリ(SwiftUI + CloudKit)
└── web-prototype/     # 最初に作ったWebプロトタイプ
```

## Developer Program 承認後にやること(一時変更の復元)

- [x] pbxproj に CODE_SIGN_ENTITLEMENTS を戻す(2026-07-20 完了)
- [x] Info.plist の AshiatoCloudEnabled を true に戻す(2026-07-20 完了)
- [x] Team昇格を確認し実機に署名ビルドをインストール(iCloudコンテナ iCloud.com.tk634.Ashiato も自動作成済み)

## プレミアムの試し方(開発中)

1. 手軽に機能だけ試す: アプリの「?」→ 使い方 → **開発用「プレミアムを試す」をON**
   (DEBUGビルドのみ。配信版には含まれない)
2. 購入フローごと試す: Xcode → Product → Scheme → Edit Scheme → Run → Options →
   **StoreKit Configuration に `Ashiato.storekit` を選択** → ⌘R
   → ペイウォールの「購入」で実際のシート(無料トライアル1週間・月額300円)が出る。
     購入・解約・復元をApp Store Connectなしで検証できる
3. 本番前の最終確認: App Store Connect の Sandbox テスターで実購入フローを確認

## リリース後に検討(保存先)

- [ ] iCloud容量の苦情が出たら、写真・動画を Cloudflare R2 に移す(比較と手順は appstore/storage-options.md)
  - Sign in with Apple / Workers で署名つきURL / アカウント削除 / プライバシー表示の変更 が必要
