import Foundation
import CoreData

/// 「ひとりが課金すれば、共有相手も使える」仕組み(ファミリープラン相当)。
///
/// 仕組み: 課金者が記録帳(TravelLog)の premiumUntil を先の日付に更新し、
/// CloudKitで共有相手にも同期される。相手は自分が未課金でも、
/// この日付が未来ならプレミアム機能(写真)を使える。
///
/// 上限: CKShare 自体は100人まで参加できるが(Apple)、
/// 1人の課金で無制限に使われるのを防ぐため、アプリ側で
/// Appleのファミリー共有と同じ6人(自分+5人)を上限とする。
enum SharedPremium {

    /// 共有プレミアムを使える人数の上限(自分を含む)
    static let maxMembers = 6

    /// 課金が切れてもすぐ止めないための猶予(同期の遅延・オフライン対策)
    private static let grace: TimeInterval = 60 * 60 * 24 * 3   // 3日

    /// 記録帳が共有プレミアム状態か
    static func isActive(_ log: TravelLog?) -> Bool {
        guard let until = log?.premiumUntil else { return false }
        return until.addingTimeInterval(grace) > Date()
    }

    /// 課金者が呼ぶ: 記録帳に有効期限を書き込んで共有相手へ伝える
    static func markActive(log: TravelLog, in context: NSManagedObjectContext) {
        // 期限は「今から35日後」。課金が続く限りアプリ起動のたびに延長される
        let next = Date().addingTimeInterval(60 * 60 * 24 * 35)
        // 毎回書き換えると同期が増えるので、残り30日を切ったときだけ更新
        if let cur = log.premiumUntil, cur.timeIntervalSinceNow > 60 * 60 * 24 * 30 { return }
        log.premiumUntil = next
        try? context.save()
    }

    /// 課金が切れた/未課金の場合に呼ぶ(自分がオーナーのときのみ)
    static func clear(log: TravelLog, in context: NSManagedObjectContext) {
        guard log.premiumUntil != nil else { return }
        log.premiumUntil = nil
        try? context.save()
    }

    /// 上限に達しているか(メンバー数で判定)
    static func isOverLimit(memberCount: Int) -> Bool {
        memberCount > maxMembers
    }
}
