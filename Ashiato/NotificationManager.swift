import Foundation
import CoreData
import UserNotifications
import CloudKit

/// 共有相手の変更を検知してローカル通知で知らせる。
/// CloudKitのプッシュ(サイレント)を Core Data が受け取り、
/// リモート変更通知が飛んでくるのを利用する(専用サーバー不要)。
///
/// 以前は件数の増減だけで判定していたため、自分で追加した場所・リアクションにも
/// 「届きました」と通知することがあった。いまは変更の履歴(Persistent History)を見て、
/// このアプリ自身の書き込み(transactionAuthor == appAuthor)を除いた「他から届いた変更」だけを通知する。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// このiPhoneでの書き込みに付ける印(Persistence で viewContext に設定する)
    nonisolated static let appAuthor = "app"

    private var observer: NSObjectProtocol?
    /// ここまでの変更は処理済み
    private var lastToken: NSPersistentHistoryToken?

    private init() {}

    /// 通知の許可を求める(オンボーディング後・招待後などに呼ぶ)
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 共有相手による変更の監視を開始
    func startObserving(container: NSPersistentContainer) {
        guard observer == nil else { return }
        // 起動時点までの変更は通知しない
        lastToken = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChange(container: container) }
        }
    }

    private struct Found {
        var places: [Place] = []
        var trips: [Trip] = []
        var photos: [Attachment] = []
        var comments: [Attachment] = []
        var reactions: [Reaction] = []
    }

    private func handleRemoteChange(container: NSPersistentContainer) {
        let ctx = container.viewContext
        let req = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
        guard let result = try? ctx.execute(req) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction],
              !transactions.isEmpty else { return }
        lastToken = transactions.last?.token

        var found = Found()
        for tx in transactions where tx.author != Self.appAuthor {
            for change in tx.changes ?? [] where change.changeType == .insert {
                guard let obj = try? ctx.existingObject(with: change.changedObjectID) else { continue }
                switch obj {
                case let p as Place: found.places.append(p)
                case let t as Trip: found.trips.append(t)
                case let a as Attachment:
                    if a.imageData != nil { found.photos.append(a) }
                    else if !(a.comment ?? "").isEmpty { found.comments.append(a) }
                case let r as Reaction: found.reactions.append(r)
                default: break
                }
            }
        }
        // 自分の名前での書き込み(同じApple IDの別のiPhoneなど)は通知しない
        let me = myName(in: ctx)
        found.photos.removeAll { me != nil && $0.authorName == me }
        found.comments.removeAll { me != nil && $0.authorName == me }
        found.reactions.removeAll { me != nil && $0.authorName == me }
        notifySummary(found)
    }

    private func notifySummary(_ f: Found) {
        // 共有に参加した直後などの大量の取り込みは、1件にまとめて知らせる
        if f.places.count > 3 {
            notify(title: "あしあとが増えました", body: "\(f.places.count)か所のあしあとが追加されました。")
        } else {
            for p in f.places {
                notify(title: "あしあとが増えました", body: "「\(p.name ?? "新しい場所")」のあしあとが追加されました。")
            }
        }
        for t in f.trips.prefix(3) {
            notify(title: "旅ができました", body: "「\(t.displayName)」の旅が作られました。")
        }
        // 写真は場所ごとにまとめる(新しく追加された場所の写真は、場所の通知に含める)
        let newPlaceIDs = Set(f.places.map(\.objectID))
        let photosByPlace = Dictionary(grouping: f.photos.filter {
            $0.place.map { !newPlaceIDs.contains($0.objectID) } ?? false
        }) { $0.place?.objectID }
        for (_, photos) in photosByPlace.prefix(3) {
            let who = photos.first?.authorName ?? "だれか"
            let where_ = photos.first?.place?.name ?? "あしあと"
            notify(title: "写真が届きました", body: "\(who) が「\(where_)」に写真を\(photos.count)枚追加しました。")
        }
        for c in f.comments.prefix(3) {
            let who = c.authorName ?? "だれか"
            let where_ = c.place?.name ?? "あしあと"
            notify(title: "ひとことが届きました", body: "\(who)「\(c.comment ?? "")」(\(where_))")
        }
        for r in f.reactions.prefix(3) {
            let who = r.authorName ?? "だれか"
            let where_ = r.place?.name ?? "あしあと"
            notify(title: "リアクションが届きました",
                   body: "\(who) が「\(where_)」に \(r.emoji ?? "❤️") を送りました。")
        }
    }

    /// このiPhoneの「自分」の名前
    private func myName(in ctx: NSManagedObjectContext) -> String? {
        guard let idString = UserDefaults.standard.string(forKey: "myMemberID"),
              let id = UUID(uuidString: idString) else { return nil }
        let req = NSFetchRequest<Member>(entityName: "Member")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first?.name
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
