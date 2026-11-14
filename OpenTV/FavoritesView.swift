import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var appState: AppState
    var onPlay: (Channel) -> Void

    var favoriteChannels: [Channel] {
        appState.enabledChannels
            .filter { appState.favorites.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            if favoriteChannels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Tap the star on any channel to add it here.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Favorites")
            } else {
                List {
                    ForEach(favoriteChannels) { channel in
                        ChannelRow(channel: channel, nowPlaying: nowPlayingTitle(for: channel))
                            .contentShape(Rectangle())
                            .onTapGesture { onPlay(channel) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.toggleFavorite(channel)
                                } label: {
                                    Label("Remove", systemImage: "star.slash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Favorites")
            }
        }
    }

    private func nowPlayingTitle(for channel: Channel) -> String? {
        guard let epgID = channel.epgID else { return nil }
        return appState.epgStore.currentProgramme(for: epgID)?.title
    }
}
