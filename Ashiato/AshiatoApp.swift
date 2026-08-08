import SwiftUI
import CoreData

@main
struct AshiatoApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(store)
                .fontDesign(.rounded)          // 全体を丸みのあるフォントに
                .tint(AppPalette.accent)       // アクセントカラーで統一
                .environment(\.locale, Locale(identifier: "ja_JP"))  // 日付UI等を常に日本語表記に
                .task {
                    // 共有相手の追加・リアクションを検知してローカル通知
                    NotificationManager.shared.startObserving(container: persistence.container)
                }
        }
    }
}
