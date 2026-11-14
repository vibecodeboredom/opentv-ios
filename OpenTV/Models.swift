import Foundation

/// A TV channel from an M3U playlist.
struct Channel: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var group: String
    var logoURL: String?
    var streamURL: String
    var playlistID: UUID
    /// The tvg-id used to match this channel against the XMLTV guide.
    var epgID: String?
}

/// An M3U playlist source (remote URL or imported file).
struct Playlist: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var urlString: String?
    var localFileName: String?
    var isEnabled: Bool
    var channelCount: Int

    var sourceDescription: String {
        if let urlString { return urlString }
        if localFileName != nil { return "Imported file" }
        return ""
    }
}

/// One programme from the XMLTV guide.
struct Programme: Identifiable, Hashable {
    var id: String
    var channelID: String
    var title: String
    var start: Date
    var stop: Date
    var description: String?
}
