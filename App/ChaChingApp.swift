import SwiftUI

@main
struct ChaChingApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }

                    Task {
                        await store.loadRemoteFamilyStateIfSignedIn()
                    }
                }
        }
    }
}
