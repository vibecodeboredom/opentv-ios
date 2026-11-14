import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedChannel: Channel?
    @State private var didAutoResume = false

    var body: some View {
        TabView {
            ChannelListView(onPlay: { selectedChannel = $0 })
                .tabItem { Label("Channels", systemImage: "tv") }
            GuideView(onPlay: { selectedChannel = $0 })
                .tabItem { Label("Guide", systemImage: "list.bullet.rectangle") }
            FavoritesView(onPlay: { selectedChannel = $0 })
                .tabItem { Label("Favorites", systemImage: "star.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            await appState.reloadAllPlaylists()
            if !didAutoResume {
                didAutoResume = true
                // Resume the last-watched channel, like the Android app.
                if let last = appState.lastChannel() {
                    selectedChannel = last
                }
            }
        }
        .fullScreenCover(item: $selectedChannel) { channel in
            PlayerView(channel: channel)
        }
    }
}
