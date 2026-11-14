import Foundation

/// Minimal M3U / M3U8 playlist parser.
///
/// Handles `#EXTINF:` lines with `key="value"` attributes
/// (tvg-id, tvg-name, tvg-logo, group-title, ...) followed by the
/// display name after the first comma that is not inside quotes,
/// then the stream URL on the next non-comment line.
enum M3UParser {
    static func parse(_ text: String, playlistID: UUID) -> [Channel] {
        var channels: [Channel] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF:") {
                let info = parseExtinf(line)
                // The stream URL is the next non-empty, non-comment line.
                var j = i + 1
                var url: String? = nil
                while j < lines.count {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    if candidate.isEmpty { j += 1; continue }
                    if candidate.hasPrefix("#") { break }
                    url = candidate
                    break
                }
                if let url, !url.isEmpty {
                    let rawID = info["tvg-id"] ?? info["tvg-name"] ?? info.name
                    let displayName = info.name.isEmpty ? (info["tvg-name"] ?? "Unknown channel") : info.name
                    channels.append(Channel(
                        id: "\(playlistID.uuidString)-\(rawID)",
                        name: displayName,
                        group: info["group-title"] ?? "Uncategorized",
                        logoURL: info["tvg-logo"],
                        streamURL: url,
                        playlistID: playlistID,
                        epgID: info["tvg-id"] ?? info["tvg-name"]
                    ))
                    i = j
                }
            }
            i += 1
        }
        return channels
    }

    private struct Extinf {
        var name: String
        var attrs: [String: String]
        subscript(_ key: String) -> String? { attrs[key] }
    }

    private static func parseExtinf(_ line: String) -> Extinf {
        // Display name starts after the first comma that is not inside quotes.
        var inQuotes = false
        var separator: String.Index? = nil
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "\"" { inQuotes.toggle() }
            if ch == "," && !inQuotes { separator = idx; break }
            idx = line.index(after: idx)
        }
        guard let sep = separator else { return Extinf(name: "", attrs: [:]) }
        let name = String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
        let head = String(line[line.startIndex..<sep])

        // Scan key="value" pairs in the header.
        var attrs: [String: String] = [:]
        var h = head.startIndex
        while h < head.endIndex {
            while h < head.endIndex && !head[h].isLetter { h = head.index(after: h) }
            guard h < head.endIndex else { break }
            let keyStart = h
            while h < head.endIndex && (head[h].isLetter || head[h].isNumber || head[h] == "-" || head[h] == "_") {
                h = head.index(after: h)
            }
            let key = String(head[keyStart..<h])
            while h < head.endIndex && head[h] != "\"" { h = head.index(after: h) }
            guard h < head.endIndex else { break }
            h = head.index(after: h) // opening quote
            let valueStart = h
            while h < head.endIndex && head[h] != "\"" { h = head.index(after: h) }
            let value = String(head[valueStart..<h])
            if !key.isEmpty { attrs[key] = value }
            if h < head.endIndex { h = head.index(after: h) } // closing quote
        }
        return Extinf(name: name, attrs: attrs)
    }
}
