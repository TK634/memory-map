import Foundation

/// 利用者の居住国に応じて表示を切り替える。
/// 日本以外のユーザーでも「国内/海外」「制県レベル」が破綻しないようにする。
enum AppRegion {

    /// 端末の地域設定(例: "JP", "US")
    static var countryCode: String {
        Locale.current.region?.identifier ?? "JP"
    }

    /// 日本在住か(制県レベルなど日本固有の機能の出し分けに使う)
    static var isJapanBased: Bool { countryCode == "JP" }

    /// 居住国の表示名(例: 「日本」「United States」)
    static var homeCountryName: String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    /// 「国内」フィルターのラベル。日本以外では国名を出す
    static var homeLabel: String {
        isJapanBased ? String(localized: "国内") : homeCountryName
    }

    /// 「海外」フィルターのラベル
    static var abroadLabel: String { String(localized: "海外") }

    /// 逆ジオコーディングやスポット検索に使うロケール(端末設定に従う)
    static var preferredLocale: Locale { Locale.current }

    /// 地域内(=居住国内)判定に使う ISO コード
    static var homeISOCode: String { countryCode }
}
