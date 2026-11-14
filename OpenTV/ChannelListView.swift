import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var appState: AppState
    var onPlay: (Channel) -> Void
    @State private var searchText = ""
    @State private var selectedGroup = "All"

    var filteredChannels: [Channel] {
        var list = appState.enabledChannels
        if selectedGroup != "All" {
            list = list.filter { $0.group == selectedGroup }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if appState.enabledChannels.isEmpty {
                    emptyState
                } else {
                    Picker("Group", selection: $selectedGroup) {
                        Text("All").tag("All")
                        ForEach(appState.groups, id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    List(filteredChannels) { channel in
                        ChannelRow(channel: channel, nowPlaying: nowPlayingTitle(for: channel))
                            .contentShape(Rectangle())
                            .onTapGesture { onPlay(channel) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Channels")
            .searchable(text: $searchText, prompt: "Search channels")
            .refreshable { await appState.reloadAllPlaylists() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No channels yet")
                .font(.headline)
            Text("Add a playlist in Settings to get started.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nowPlayingTitle(for channel: Channel) -> String? {
        guard let epgID = channel.epgID else { return nil }
        return appState.epgStore.currentProgramme(for: epgID)?.title
    }
}

struct ChannelRow: View {
    @EnvironmentObject var appState: AppState
    let channel: Channel
    let nowPlaying: String?

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(urlString: channel.logoURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .lineLimit(1)
                if let now = nowPlaying {
                    Text(now)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(channel.group)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: { appState.toggleFavorite(channel) }) {
                Image(systemName: appState.favorites.contains(channel.id) ? "star.fill" : "star")
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ChannelLogo: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "tv")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "tv")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
    }
}
