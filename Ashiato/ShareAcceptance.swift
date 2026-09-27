import SwiftUI
import UIKit
import CloudKit

extension Notification.Name {
    /// 招待リンクから記録帳に参加できた
    static let didJoinSharedLog = Notification.Name("didJoinSharedLog")
    /// 参加に失敗した(object: 理由の文字列)
    static let shareJoinFailed = Notification.Name("shareJoinFailed")
}

/// 招待リンク(iCloudの共有リンク)を開いたときの受け口。
/// iOS はリンクを開くとこのシーンデリゲートに共有の情報を渡してくる。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// アプリが起動中にリンクを開いた
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareAcceptance.accept(cloudKitShareMetadata)
    }

    /// アプリが閉じている状態でリンクから起動した
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.accept(metadata)
        }
    }
}

enum ShareAcceptance {
    static func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            do {
                try await PersistenceController.shared.acceptShare(metadata)
                NotificationCenter.default.post(name: .didJoinSharedLog, object: nil)
            } catch {
                NotificationCenter.default.post(name: .shareJoinFailed, object: error.localizedDescription)
            }
        }
    }
}

/// iOS標準の共有シート(LINE・メッセージ・メールなど、入っているアプリが並ぶ)
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
