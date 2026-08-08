import Foundation
import CoreData
import UserNotifications
import CloudKit

/// 共有相手の変更を検知してローカル通知で知らせる。
/// CloudKitのプッシュ(サイレント)を Core Data が受け取り、
/// リモート変更通知が飛んでくるのを利用する(専用サーバー不要)。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var observer: NSObjectProtocol?
    /// 直近に見たオブジェクト数(増分検知用)
    private var lastPlaceCount = 0
    private var lastReactionCount = 0
    private var isPrimed = false

    private init() {}

    /// 通知の許可を求める(オンボーディング後・招待後などに呼ぶ)
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 共有相手による変更の監視を開始
    func startObserving(container: NSPersistentContainer) {
        guard observer == nil else { return }
        prime(container: container)
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChange(container: container) }
        }
    }

    /// 現在の件数を基準値として記録
    private func prime(container: NSPersistentContainer) {
        let ctx = container.viewContext
        lastPlaceCount = (try? ctx.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Place"))) ?? 0
        lastReactionCount = (try? ctx.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Reaction"))) ?? 0
        isPrimed = true
    }

    private func handleRemoteChange(container: NSPersistentContainer) {
        let ctx = container.viewContext
        ctx.refreshAllObjects()
        guard isPrimed else { prime(container: container); return }

        let places = (try? ctx.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Place"))) ?? 0
        let reactions = (try? ctx.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Reaction"))) ?? 0

        if places > lastPlaceCount {
            // 直近に追加された場所の名前を拾って通知
            let req = NSFetchRequest<Place>(entityName: "Place")
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            req.fetchLimit = 1
            let name = (try? ctx.fetch(req))?.first?.name ?? "新しい場所"
            notify(title: "あしあとが増えました",
                   body: "「\(name)」のあしあとが追加されました。")
        }
        if reactions > lastReactionCount {
            let req = NSFetchRequest<Reaction>(entityName: "Reaction")
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            req.fetchLimit = 1
            if let r = (try? ctx.fetch(req))?.first {
                let who = r.authorName ?? "だれか"
                let where_ = r.place?.name ?? "あしあと"
                notify(title: "リアクションが届きました",
                       body: "\(who) が「\(where_)」に \(r.emoji ?? "❤️") を送りました。")
            }
        }
        lastPlaceCount = places
        lastReactionCount = reactions
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
