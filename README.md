# あしあと (Ashiato)

訪れた場所を地図にピンで記録し、iCloudで夫婦・友達と共有できるiPhoneアプリ。

- `Ashiato.xcodeproj` — Xcodeプロジェクト(これを開いて開発)
- `Ashiato/` — アプリ本体のソース(SwiftUI + MapKit + CloudKit + StoreKit 2)
- `web-prototype/` — 機能検証用のWebプロトタイプ(index.html をブラウザで開くだけで動作)
- `DESIGN.md` — 設計・今後の対応方針
- `TODO.md` — リリースまでのやることリスト

## セットアップの残り(Xcode上)

1. Signing & Capabilities で Team を選択し、以下を追加:
   - **iCloud** → CloudKit → コンテナ作成(例: `iCloud.com.あなたのID.Ashiato`)
   - **Background Modes** → Remote notifications
   - **In-App Purchase**
2. `Ashiato/Persistence.swift` の `cloudKitContainerID` を作成したコンテナIDに書き換え
3. Target → General → Display Name を「あしあと」に設定
4. App Store Connect でサブスク商品 `ashiato.premium.monthly` を作成(価格・無料トライアル1週間)

## 申請前の注意

- CloudKit Console でスキーマを **Production にデプロイ**(忘れると製品版で同期しない)
- 位置情報は地図タップ時の逆ジオコーディングのみで、現在地は取得しないため位置情報の許可は不要
- 詳細は `TODO.md` を参照
