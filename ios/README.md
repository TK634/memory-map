# メモリーマップ — iOSアプリ(Apple純正 CloudKit版)

訪れた場所を地図にピンで記録し、iCloudで夫婦・友達と共有できるiPhoneアプリです。
サーバー不要・追加費用なし(Apple IDだけで同期・共有)。

> **アプリ名について**: ホーム画面に表示される名前は Xcode の
> Target → General → Display Name に「メモリーマップ」と入力して設定します。
> (プロジェクト内部名は英数字の `TabiNoKiroku` のままで問題ありません)

## 機能

- MapKitの地図をタップ、または検索で訪問地を追加(国内=手動/自動判定、逆ジオコーディングで地名を自動入力)
- メンバー登録(色付き)。ピンの色で「誰が行ったか」が分かる
  - 1人だけ → その人の色 / 全員一緒 → 緑 / 一部の人 → 紫
- フィルター:行った人 / 「〜だけ」(その人が1人で行った場所) / 国内・海外 / 年
- 訪問数ランキング(年・区分フィルターと連動)
- **iCloud同期**:自分のiPhone・iPad間は自動同期
- **iCloud共有**:共有ボタン(↑)からパートナーを招待。相手のiPhoneでも同じ記録を閲覧・編集可能

## 必要なもの

- Mac + Xcode 15以上
- Apple Developer Program(App Store配信・CloudKit利用に必要 / 年99ドル)
- iOS 17以上の実機(CloudKit共有のテストはシミュレータ不可。Apple IDが2つあると招待の動作確認ができます)

## セットアップ手順

1. **Xcodeで新規プロジェクト作成**
   - File → New → Project → iOS → App
   - Product Name: `TabiNoKiroku` / Interface: SwiftUI / Language: Swift
   - 「Use Core Data」「Host in CloudKit」は**チェック不要**(このフォルダのファイルで置き換えるため)

2. **ファイルを差し替え**
   - 自動生成された `ContentView.swift` と `TabiNokirokuApp.swift` を削除
   - このフォルダ内の `.swift` ファイル7つと `TabiNoKiroku.xcdatamodeld` をプロジェクトにドラッグ&ドロップ
     (「Copy items if needed」にチェック)

3. **Capabilities を追加**(Signing & Capabilities タブ)
   - `iCloud` を追加 → CloudKit にチェック → コンテナを新規作成
     (例: `iCloud.com.あなたのID.TabiNoKiroku`)
   - `Background Modes` を追加 → Remote notifications にチェック
   - `In-App Purchase` を追加(プレミアムのサブスク課金に必要)
   - `Persistence.swift` の `cloudKitContainerID` を作成したコンテナIDに書き換える

   **サブスク商品の作成**(App Store Connect)
   - 自動更新サブスクリプションを作成し、プロダクトIDを
     `memorymap.premium.monthly`(`StoreManager.premiumProductID` と一致)にする
   - 無料トライアル(例: 1週間)と価格を設定
   - 実機テスト前は Xcode の StoreKit Configuration ファイル、または
     App Store Connect の Sandbox テスターで購入・復元・解約を確認

4. **実機で実行**
   - iPhoneにiCloudサインイン済みであることを確認して Run

5. **共有のテスト**
   - 右上の共有ボタン(↑)→ メッセージ等でパートナーに招待リンクを送信
   - 相手がリンクを開くとアプリが起動し、同じ記録を共同編集できます

## App Store 申請時の注意

- App Store Connect でアプリ登録後、CloudKitコンテナのスキーマを
  **Production環境にデプロイ**すること(CloudKit Console → Deploy Schema Changes)。
  これを忘れると審査版・製品版で同期しません。
- 位置情報は「地図タップ時の逆ジオコーディング」にのみ使用し、
  ユーザーの現在地は取得していないため位置情報の許可は不要です。

## 構成

| ファイル | 役割 |
|---|---|
| `TabiNoKirokuApp.swift` | エントリポイント |
| `Persistence.swift` | Core Data + CloudKit 同期・CKShare共有 |
| `ModelHelpers.swift` | フィルターロジック・色・モデル拡張 |
| `ContentView.swift` | 地図・検索・フィルターバー |
| `AddEditPlaceView.swift` | 訪問地の追加・編集(プレミアム: 写真・コメント) |
| `OtherViews.swift` | メンバー管理・ランキング・一覧・共有シート |
| `StoreManager.swift` | StoreKit 2 サブスク(購入・状態監視・復元) |
| `PaywallView.swift` | ペイウォール画面 |
| `TabiNoKiroku.xcdatamodeld` | データモデル(TravelLog / Place / Member / Attachment) |

## 注意

このコードはXcode外で書かれたスキャフォールドです。Xcodeのバージョンにより
微修正(APIの差分など)が必要な場合があります。ビルドエラーが出たら
エラーメッセージと該当箇所を添えて相談してください。
