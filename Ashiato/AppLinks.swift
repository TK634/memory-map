import Foundation

/// アプリ外のページへのリンク。App Store Connect に登録するURLと同じものを使う。
enum AppLinks {
    /// 利用規約: Apple標準の使用許諾契約(EULA)
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// プライバシーポリシー(GitHub Pages: リポジトリの docs/privacy.html)
    static let privacyPolicy = URL(string: "https://tk634.github.io/memory-map/privacy.html")!
    /// サポート・お問い合わせ(GitHub Pages: リポジトリの docs/index.html)
    static let support = URL(string: "https://tk634.github.io/memory-map/")!
}
