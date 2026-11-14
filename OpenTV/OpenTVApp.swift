import SwiftUI

@main
struct OpenTVApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    // Refresh the guide in the background (skipped if fresh).
                    await appState.refreshEPG()
                }
        }
    }
}
