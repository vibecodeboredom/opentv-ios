import Foundation

/// Streaming XMLTV parser. Programmes are written to the EPG store in
/// batches as they are parsed, so large guides (tens of MB) do not
/// have to be held in memory.
final class EPGParser: NSObject, XMLParserDelegate {
    private let store: EPGStore
    private var batch: [Programme] = []
    private var channelNames: [String: String] = [:]
    private var currentChannelID: String?
    private var currentDisplayName = ""
    private var progChannel = ""
    private var progStart = ""
    private var progStop = ""
    private var progTitle = ""
    private var progDesc = ""
    private var text = ""
    private let dateFormatter: DateFormatter
    private let dateFormatterNoSpace: DateFormatter
    private(set) var programmeCount = 0

    init(store: EPGStore) {
        self.store = store
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMddHHmmss Z"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatterNoSpace = DateFormatter()
        dateFormatterNoSpace.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterNoSpace.dateFormat = "yyyyMMddHHmmssZ"
        dateFormatterNoSpace.timeZone = TimeZone(secondsFromGMT: 0)
        super.init()
    }

    func parse(data: Data) throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        if !parser.parse() {
            if let error = parser.parserError { throw error }
            throw NSError(domain: "OpenTV", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to parse the EPG guide."
            ])
        }
        flushBatch()
        store.replaceChannelNames(channelNames)
    }

    private func flushBatch() {
        if !batch.isEmpty {
            store.insertProgrammes(batch)
            programmeCount += batch.count
            batch.removeAll(keepingCapacity: true)
        }
    }

    private func parseDate(_ string: String) -> Date? {
        // XMLTV dates look like "20261114120000 +0000".
        if let date = dateFormatter.date(from: string) { return date }
        return dateFormatterNoSpace.date(from: string)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "channel", let id = attributeDict["id"] {
            currentChannelID = id
            currentDisplayName = ""
        } else if elementName == "programme" {
            progChannel = attributeDict["channel"] ?? ""
            progStart = attributeDict["start"] ?? ""
            progStop = attributeDict["stop"] ?? ""
            progTitle = ""
            progDesc = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name":
            if currentChannelID != nil, !value.isEmpty { currentDisplayName = value }
        case "channel":
            if let id = currentChannelID, !currentDisplayName.isEmpty {
                channelNames[id] = currentDisplayName
            }
            currentChannelID = nil
        case "title":
            progTitle = value
        case "desc":
            progDesc = value
        case "programme":
            if let start = parseDate(progStart),
               let stop = parseDate(progStop),
               !progChannel.isEmpty, !progTitle.isEmpty {
                batch.append(Programme(
                    id: "\(progChannel)-\(Int(start.timeIntervalSince1970))",
                    channelID: progChannel,
                    title: progTitle,
                    start: start,
                    stop: stop,
                    description: progDesc.isEmpty ? nil : progDesc
                ))
                if batch.count >= 2000 { flushBatch() }
            }
        default:
            break
        }
        text = ""
    }
}
