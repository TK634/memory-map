# あしあと — やることリスト

iPhoneアプリ「あしあと」をApp Storeでリリースするまでのタスク一覧。

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
- [x] `PaywallView.swift`: ペイウォール画面(継続的価値の明示: 写真・コメント無制限+今後の機能追加)
- [x] `AddEditPlaceView` に写真(PhotosUI)・コメント欄を追加、未課金時はペイウォールへ誘導
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
- [ ] 審査メモにサブスクの継続的価値(写真・コメント機能、今後のアップデート計画)を記載
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
