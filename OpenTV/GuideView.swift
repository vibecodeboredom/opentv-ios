import SwiftUI

/// EPG guide: one row per channel with what's on now, expandable to
/// show programmes from 4 hours back to 12 hours ahead.
/// Tapping a channel plays it.
struct GuideView: View {
    @EnvironmentObject var appState: AppState
    var onPlay: (Channel) -> Void
    @State private var expandedChannelID: String?
    @State private var searchText = ""

    var channels: [Channel] {
        let list = appState.enabledChannels.sorted { $0.name < $1.name }
        if searchText.isEmpty { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(channels) { channel in
                GuideChannelRow(
                    channel: channel,
                    expanded: expandedChannelID == channel.id,
                    onPlay: onPlay,
                    onToggleExpand: {
                        if expandedChannelID == channel.id {
                            expandedChannelID = nil
                        } else {
                            expandedChannelID = channel.id
                        }
                    }
                )
            }
            .listStyle(.plain)
            .navigationTitle("Guide")
            .searchable(text: $searchText, prompt: "Search channels")
        }
    }
}

struct GuideChannelRow: View {
    @EnvironmentObject var appState: AppState
    let channel: Channel
    let expanded: Bool
    var onPlay: (Channel) -> Void
    var onToggleExpand: () -> Void

    var programmes: [Programme] {
        guard let epgID = channel.epgID else { return [] }
        let from = Date().addingTimeInterval(-4 * 3600)
        let to = Date().addingTimeInterval(12 * 3600)
        return appState.epgStore.programmes(for: epgID, from: from, to: to)
    }

    var now: Programme? {
        guard let epgID = channel.epgID else { return nil }
        return appState.epgStore.currentProgramme(for: epgID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ChannelLogo(urlString: channel.logoURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .lineLimit(1)
                    if let current = now {
                        Text("Now: \(current.title)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("No guide data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Play") { onPlay(channel) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: onToggleExpand) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { onPlay(channel) }

            if expanded {
                if programmes.isEmpty {
                    Text("No programmes in the guide for this channel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(programmes) { programme in
                        ProgrammeRow(programme: programme, isNow: now?.id == programme.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProgrammeRow: View {
    let programme: Programme
    let isNow: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(Self.timeFormatter.string(from: programme.start)) – \(Self.timeFormatter.string(from: programme.stop))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 118, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(programme.title)
                    .font(.subheadline)
                    .fontWeight(isNow ? .bold : .regular)
                if let description = programme.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
