import SwiftUI
import AVKit

/// Full-screen player for one channel, with dead-stream retries.
/// Retries up to 3 times, then shows a clear error instead of hanging.
struct PlayerView: View {
    let channel: Channel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel

    init(channel: Channel) {
        self.channel = channel
        _viewModel = StateObject(wrappedValue: PlayerViewModel(channel: channel))
    }

    var body: some View {
        ZStack {
            PlayerControllerView(player: viewModel.player)
                .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Loading \(channel.name)…")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
            }

            if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(error)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button("Retry") { viewModel.retry() }
                            .buttonStyle(.borderedProminent)
                        Button("Close") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.75))
                .cornerRadius(14)
                .padding()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear { appState.setLastChannel(channel) }
        .onDisappear { viewModel.stop() }
    }
}

final class PlayerViewModel: NSObject, ObservableObject {
    @Published var player = AVPlayer()
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let channel: Channel
    private var attempts = 0
    private let maxAttempts = 3
    private var statusObservation: NSKeyValueObservation?
    private var stallObserver: NSObjectProtocol?
    private var retryPending = false
    private var stopped = false

    init(channel: Channel) {
        self.channel = channel
        super.init()
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFailure("The stream stalled.")
        }
        load()
    }

    deinit {
        statusObservation?.invalidate()
        if let observer = stallObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func load() {
        retryPending = false
        guard let url = URL(string: channel.streamURL) else {
            isLoading = false
            errorMessage = "This channel doesn't have a valid stream URL."
            return
        }
        attempts += 1
        isLoading = true
        errorMessage = nil
        let item = AVPlayerItem(url: url)
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard let self else { return }
            if observed.status == .readyToPlay {
                self.isLoading = false
                self.player.play()
            } else if observed.status == .failed {
                self.handleFailure(observed.error?.localizedDescription ?? "Failed to load the stream.")
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func retry() {
        attempts = 0
        load()
    }

    func stop() {
        stopped = true
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func handleFailure(_ message: String) {
        guard !stopped, !retryPending else { return }
        if attempts < maxAttempts {
            retryPending = true
            isLoading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, !self.stopped else { return }
                self.load()
            }
        } else {
            isLoading = false
            errorMessage = "Couldn't play this channel after \(maxAttempts) tries. The stream may be offline.\n\(message)"
        }
    }
}

struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
