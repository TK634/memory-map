import SwiftUI

@main
struct TabiNoKirokuApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(store)
        }
    }
}
