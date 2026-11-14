import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var epgURLText = ""
    @State private var showingFileImporter = false
    @State private var showingAddPlaylist = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Playlists")) {
                    if appState.playlists.isEmpty {
                        Text("No playlists added yet.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(appState.playlists) { playlist in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                Text("\(playlist.channelCount) channels · \(playlist.sourceDescription)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { playlist.isEnabled },
                                set: { appState.setPlaylistEnabled(playlist, enabled: $0) }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            appState.removePlaylist(appState.playlists[index])
                        }
                    }
                    Button("Add playlist by URL") { showingAddPlaylist = true }
                    Button("Import playlist file (.m3u)") { showingFileImporter = true }
                    Button("Add PlutoTV (US) sample playlist") {
                        Task {
                            await appState.addPlaylist(name: "PlutoTV US", urlString: AppState.samplePlaylistURL)
                        }
                    }
                }

                Section(header: Text("Guide (EPG)")) {
                    TextField("EPG URL", text: $epgURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Last updated")
                        Spacer()
                        Text(appState.epgLastUpdated.map {
                            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
                        } ?? "Never")
                        .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Programmes cached")
                        Spacer()
                        Text("\(appState.epgProgrammeCount)")
                            .foregroundColor(.secondary)
                    }
                    Button(appState.isRefreshingEPG ? "Refreshing…" : "Refresh guide now") {
                        Task { await appState.refreshEPG(force: true) }
                    }
                    .disabled(appState.isRefreshingEPG)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    Text("OpenTV for iOS — free, open-source IPTV player. M3U playlists + XMLTV guide.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { epgURLText = appState.epgURLString }
            .onChange(of: epgURLText) { newValue in
                appState.epgURLString = newValue
                appState.saveSettings()
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { appState.errorMessage != nil },
                    set: { if !$0 { appState.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
            .sheet(isPresented: $showingAddPlaylist) {
                AddPlaylistSheet()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        appState.importPlaylistFile(
                            name: url.deletingPathExtension().lastPathComponent,
                            data: data
                        )
                    }
                case .failure(let error):
                    appState.errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AddPlaylistSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $name)
                TextField("Playlist URL (.m3u)", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .navigationTitle("Add playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await appState.addPlaylist(name: name, urlString: urlString)
                            dismiss()
                        }
                    }
                    .disabled(urlString.isEmpty)
                }
            }
        }
    }
}
