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

        // まずiCloud同期ありで試し、失敗したらローカルのみで開き直す
        // (iCloud entitlementsのない署名・iCloudオフの端末でも起動できるように)
        container.persistentStoreDescriptions = makeDescriptions(cloud: true)
        var cloudError: Error?
        container.loadPersistentStores { _, error in
            if let error { cloudError = error }
        }
        if cloudError != nil {
            isCloudEnabled = false
            container.persistentStoreDescriptions = makeDescriptions(cloud: false)
            container.loadPersistentStores { _, error in
                if let error { fatalError("Core Data 読み込み失敗(ローカル): \(error)") }
            }
            print("[Persistence] iCloud同期を無効化しローカルのみで動作します: \(cloudError!)")
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
