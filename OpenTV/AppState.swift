import Foundation
import Combine

/// Shared app state: playlists, channels, favorites, last channel,
/// and the EPG guide. Persisted in UserDefaults; the guide itself
/// lives in the SQLite EPG store.
@MainActor
final class AppState: ObservableObject {
    static let defaultEPGURL = "https://i.mjh.nz/PlutoTV/us.xml"
    static let samplePlaylistURL = "https://iptv-org.github.io/iptv/countries/us.m3u"

    @Published var playlists: [Playlist] = []
    @Published var channels: [Channel] = []
    @Published var favorites: Set<String> = []
    @Published var lastChannelID: String?
    @Published var epgURLString: String = defaultEPGURL
    @Published var epgLastUpdated: Date?
    @Published var epgProgrammeCount: Int = 0
    @Published var isLoadingPlaylists = false
    @Published var isRefreshingEPG = false
    @Published var errorMessage: String?

    let epgStore = EPGStore()
    private let defaults = UserDefaults.standard

    var enabledChannels: [Channel] {
        let enabledIDs = Set(playlists.filter { $0.isEnabled }.map { $0.id })
        return channels.filter { enabledIDs.contains($0.playlistID) }
    }

    var groups: [String] {
        Array(Set(enabledChannels.map { $0.group })).sorted()
    }

    init() {
        loadSettings()
        epgProgrammeCount = epgStore.programmeCount()
    }

    // MARK: - Persistence

    private struct SavedState: Codable {
        var playlists: [Playlist]
        var favorites: [String]
        var lastChannelID: String?
        var epgURLString: String
        var epgLastUpdated: Date?
    }

    private func loadSettings() {
        if let data = defaults.data(forKey: "opentv.state"),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            playlists = saved.playlists
            favorites = Set(saved.favorites)
            lastChannelID = saved.lastChannelID
            epgURLString = saved.epgURLString.isEmpty ? Self.defaultEPGURL : saved.epgURLString
            epgLastUpdated = saved.epgLastUpdated
        }
    }

    func saveSettings() {
        let saved = SavedState(
            playlists: playlists,
            favorites: Array(favorites),
            lastChannelID: lastChannelID,
            epgURLString: epgURLString,
            epgLastUpdated: epgLastUpdated
        )
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "opentv.state")
        }
    }

    // MARK: - Playlists

    func addPlaylist(name: String, urlString: String) async {
        guard let url = URL(string: urlString) else {
            errorMessage = "That playlist URL doesn't look right."
            return
        }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not read that playlist."
                return
            }
            var playlist = Playlist(
                id: UUID(),
                name: name.isEmpty ? (url.host ?? "Playlist") : name,
                urlString: urlString,
                localFileName: nil,
                isEnabled: true,
                channelCount: 0
            )
            let parsed = M3UParser.parse(text, playlistID: playlist.id)
            playlist.channelCount = parsed.count
            playlists.append(playlist)
            channels.append(contentsOf: parsed)
            saveSettings()
        } catch {
            errorMessage = "Failed to load playlist: \(error.localizedDescription)"
        }
    }

    func importPlaylistFile(name: String, data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            errorMessage = "Could not read that playlist file."
            return
        }
        var playlist = Playlist(
            id: UUID(),
            name: name,
            urlString: nil,
            localFileName: nil,
            isEnabled: true,
            channelCount: 0
        )
        let parsed = M3UParser.parse(text, playlistID: playlist.id)
        playlist.channelCount = parsed.count
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileURL = dir.appendingPathComponent("\(playlist.id.uuidString).m3u")
        try? data.write(to: fileURL)
        playlist.localFileName = fileURL.lastPathComponent
        playlists.append(playlist)
        channels.append(contentsOf: parsed)
        saveSettings()
    }

    func reloadAllPlaylists() async {
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        var newChannels: [Channel] = []
        for playlist in playlists {
            do {
                let text: String
                if let urlString = playlist.urlString, let url = URL(string: urlString) {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let parsed = String(data: data, encoding: .utf8) else { continue }
                    text = parsed
                } else if let file = playlist.localFileName {
                    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
                } else {
                    continue
                }
                let parsed = M3UParser.parse(text, playlistID: playlist.id)
                newChannels.append(contentsOf: parsed)
                if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                    playlists[idx].channelCount = parsed.count
                }
            } catch {
                // Keep the old channels for this playlist if the reload fails.
                newChannels.append(contentsOf: channels.filter { $0.playlistID == playlist.id })
            }
        }
        channels = newChannels
        saveSettings()
    }

    func removePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        channels.removeAll { $0.playlistID == playlist.id }
        if let file = playlist.localFileName {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
        saveSettings()
    }

    func setPlaylistEnabled(_ playlist: Playlist, enabled: Bool) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[idx].isEnabled = enabled
            saveSettings()
        }
    }

    // MARK: - Favorites / last channel

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.id) {
            favorites.remove(channel.id)
        } else {
            favorites.insert(channel.id)
        }
        saveSettings()
    }

    func setLastChannel(_ channel: Channel) {
        lastChannelID = channel.id
        saveSettings()
    }

    func lastChannel() -> Channel? {
        guard let id = lastChannelID else { return nil }
        return enabledChannels.first { $0.id == id }
    }

    // MARK: - EPG

    func refreshEPG(force: Bool = false) async {
        guard !isRefreshingEPG else { return }
        if !force,
           let last = epgLastUpdated,
           Date().timeIntervalSince(last) < 6 * 3600,
           epgProgrammeCount > 0 {
            return // Guide is fresh enough; skip the download.
        }
        guard let url = URL(string: epgURLString) else {
            errorMessage = "That guide URL doesn't look right."
            return
        }
        isRefreshingEPG = true
        defer { isRefreshingEPG = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let store = epgStore
            let count = try await Task.detached(priority: .utility) {
                store.clearAll()
                let parser = EPGParser(store: store)
                try parser.parse(data: data)
                return parser.programmeCount
            }.value
            epgProgrammeCount = count
            epgLastUpdated = Date()
            saveSettings()
        } catch {
            errorMessage = "Failed to refresh the guide: \(error.localizedDescription)"
        }
    }
}
