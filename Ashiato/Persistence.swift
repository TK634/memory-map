import CoreData
import CloudKit

/// NSPersistentCloudKitContainer を使った iCloud 同期スタック。
/// - 自分のデバイス間は自動同期(プライベートDB)
/// - 夫婦・友達との共有は CKShare(共有DB)で実現
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    /// Xcode の Signing & Capabilities で設定する iCloud コンテナIDと合わせること
    static let cloudKitContainerID = "iCloud.com.tk634.Ashiato"

    /// iCloud同期が有効か(entitlementsなし・iCloud未サインイン等ではfalseになり、ローカルのみで動作)
    private(set) var isCloudEnabled = true

    private init() {
        container = NSPersistentCloudKitContainer(name: "Ashiato")

        guard let base = container.persistentStoreDescriptions.first,
              let baseURL = base.url?.deletingLastPathComponent() else {
            fatalError("ストア設定が見つかりません")
        }

        func makeDescriptions(cloud: Bool) -> [NSPersistentStoreDescription] {
            // プライベートDB(自分のデータ)
            let privateDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("private.sqlite"))
            if cloud {
                let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
                opts.databaseScope = .private
                privateDesc.cloudKitContainerOptions = opts
            }
            privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            guard cloud else { return [privateDesc] }

            // 共有DB(相手から共有されたデータ)。ローカルモードでは使わない
            let sharedDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("shared.sqlite"))
            let sharedOpts = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            sharedOpts.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = sharedOpts
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            return [privateDesc, sharedDesc]
        }

        // iCloud同期の可否は Info.plist の AshiatoCloudEnabled で決める。
        // entitlementsのない署名でCloudKitを有効にすると、起動後に
        // バックグラウンドでキャッチ不能なクラッシュになるため(実測)、
        // entitlementsの有無とこのフラグは必ずセットで切り替えること。
        let wantCloud = (Bundle.main.object(forInfoDictionaryKey: "AshiatoCloudEnabled") as? Bool) ?? true
        isCloudEnabled = wantCloud
        container.persistentStoreDescriptions = makeDescriptions(cloud: wantCloud)
        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if loadError != nil, wantCloud {
            // 予期しない失敗時はローカルのみで開き直す(最後の砦)
            isCloudEnabled = false
            container.persistentStoreDescriptions = makeDescriptions(cloud: false)
            container.loadPersistentStores { _, error in
                if let error { fatalError("Core Data 読み込み失敗(ローカル): \(error)") }
            }
            print("[Persistence] iCloud同期を無効化しローカルのみで動作します: \(loadError!)")
        } else if let loadError {
            fatalError("Core Data 読み込み失敗: \(loadError)")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - ルート TravelLog の取得(なければ作成)

    /// 共有されたログがあればそれを優先し、なければ自分のログを返す
    func fetchOrCreateLog(in context: NSManagedObjectContext) -> TravelLog {
        let request = NSFetchRequest<TravelLog>(entityName: "TravelLog")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let logs = (try? context.fetch(request)) ?? []

        // 共有DB由来のログを優先(招待を受けた側は相手のログを使う)
        if let shared = logs.first(where: { isShared(object: $0) }) { return shared }
        if let mine = logs.first { return mine }

        let log = TravelLog(context: context)
        log.title = "あしあと"
        log.createdAt = Date()
        try? context.save()
        return log
    }

    func isShared(object: NSManagedObject) -> Bool {
        guard let store = object.objectID.persistentStore else { return false }
        return container.persistentStoreDescriptions
            .first { $0.cloudKitContainerOptions?.databaseScope == .shared }?
            .url == store.url
    }

    // MARK: - 共有(CKShare)

    /// TravelLog を共有するための CKShare を取得(なければ作成)
    /// プライベート/共有の保存先
    private func store(for scope: CKDatabase.Scope) -> NSPersistentStore? {
        guard let desc = container.persistentStoreDescriptions
                .first(where: { $0.cloudKitContainerOptions?.databaseScope == scope }),
              let url = desc.url else { return nil }
        return container.persistentStoreCoordinator.persistentStore(for: url)
    }

    /// LINEなどで送れる招待リンク。リンクを受け取った人は誰でも参加できる(読み書き可)。
    /// やめたいときは「共有の管理」から共有を止めればリンクは無効になる
    func inviteURL(for log: TravelLog) async throws -> URL {
        var (share, _) = try await getOrCreateShare(for: log)
        if share.publicPermission != .readWrite {
            // 公開範囲を変えられるのは記録帳を作った人(オーナー)だけ
            guard share.currentUserParticipant?.role == .owner || share.owner == share.currentUserParticipant,
                  let privateStore = store(for: .private) else {
                throw NSError(domain: "Ashiato", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "招待できるのは、この記録帳を作った人だけです。",
                ])
            }
            share.publicPermission = .readWrite
            share[CKShare.SystemFieldKey.title] = "あしあと" as CKRecordValue
            share = try await container.persistUpdatedShare(share, in: privateStore)
        }
        guard let url = share.url else {
            throw NSError(domain: "Ashiato", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "招待リンクを作れませんでした。通信環境を確認してもう一度お試しください。",
            ])
        }
        return url
    }

    /// 招待リンクを開いたときに呼ばれる: 相手の記録帳に参加する
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        guard isCloudEnabled, let shared = store(for: .shared) else {
            throw NSError(domain: "Ashiato", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "iCloudにサインインしてから、もう一度リンクを開いてください。",
            ])
        }
        _ = try await container.acceptShareInvitations(from: [metadata], into: shared)
    }

    func getOrCreateShare(for log: TravelLog) async throws -> (CKShare, CKContainer) {
        guard isCloudEnabled else {
            throw NSError(domain: "Ashiato", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "この端末・ビルドではiCloud同期が無効のため共有できません。",
            ])
        }
        let ckContainer = CKContainer(identifier: Self.cloudKitContainerID)
        if let existing = try? container.fetchShares(matching: [log.objectID])[log.objectID] {
            return (existing, ckContainer)
        }
        let (_, share, _) = try await container.share([log], to: nil)
        share[CKShare.SystemFieldKey.title] = "あしあと" as CKRecordValue
        return (share, ckContainer)
    }
}
