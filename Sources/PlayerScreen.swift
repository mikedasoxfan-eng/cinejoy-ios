import SwiftUI
import Observation
import WebKit
import AVKit
import AVFAudio

// Player structure (why it is shaped this way):
// - The AVPlayerViewController stays at one structural position for the whole
//   presentation (portrait, landscape, provider controls). Re-creating it during a
//   rotation or while AVKit is presenting fullscreen would drop the player.
// - Playback is stopped only by an explicit close, a replaced presentation, or the
//   resolver view being dismantled. `onDisappear` alone also fires when AVKit's
//   own fullscreen controller covers this screen, and used to kill fullscreen video.
// - High-frequency values (caption clock 10 Hz, elapsed seconds 1 Hz) are read only
//   by small leaf views, so the screen, its menus and representables do not redraw.
struct PlayerScreen: View {
    let playback: Playback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LibraryStore.self) private var library
    @State private var session = NativePlaybackSession()
    @State private var attempt = 0

    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // A real, laid-out page lets the public website resolve its player.
            // The resolver is not extracted or copied into the app.
            PlaybackResolverView(playback: playback, session: session, parked: session.websiteParked,
                                 interactive: session.showProviderControls)
                .id(attempt)
                .opacity(session.showProviderControls ? 1 : 0.001)
                .allowsHitTesting(session.showProviderControls)
                .accessibilityHidden(!session.showProviderControls)
                .ignoresSafeArea(edges: .bottom)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    PlayerStage(session: session, title: playback.title)
                        .frame(width: geometry.size.width,
                               height: landscape ? geometry.size.height : min(geometry.size.width * 9 / 16, geometry.size.height))
                    if !landscape {
                        PlayerInfoPanel(playback: playback, session: session, close: close)
                    }
                }
            }
            .ignoresSafeArea(edges: landscape ? Edge.Set.vertical : Edge.Set.bottom)
            .opacity(session.showProviderControls ? 0 : 1)
            .allowsHitTesting(!session.showProviderControls)
            .accessibilityHidden(session.showProviderControls)
            if session.error != nil, !session.showProviderControls {
                PlayerErrorView(session: session) { retry() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !landscape { PlayerTopBar(title: playback.title, episode: playback.episode, session: session, close: close) }
        }
        .safeAreaInset(edge: .leading, spacing: 0) {
            if landscape { PlayerRail(title: playback.title, session: session, close: close) }
        }
        .onAppear { connectHistory() }
        .onDisappear {
            // Covered by AVKit fullscreen or PiP: keep playing. Only a dismissed or
            // replaced presentation ends this session.
            if library.playback?.id != playback.id { finish() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.checkpoint(force: true)
                library.flush()
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(landscape)
    }

    private func connectHistory() {
        let title = playback.title
        session.onProgress = { [weak library] path, seconds, duration, force in
            library?.record(title, path: path, seconds: seconds, duration: duration, force: force)
        }
    }

    private func retry() {
        session.stop()
        attempt += 1
    }

    private func finish() {
        session.checkpoint(force: true)
        session.stop()
    }

    private func close() {
        finish()
        dismiss()
    }
}

// MARK: - Stage (video, loading)

private struct PlayerStage: View {
    let session: NativePlaybackSession
    let title: Title

    var body: some View {
        ZStack {
            Color.black
            if let player = session.player {
                // No accessibility modifiers on the representable itself: a label
                // turned AVKit's view tree into one opaque element and hid its controls.
                NativeMoviePlayer(player: player, session: session, captionsActive: session.selectedCaptionID != nil)
            }
            if session.isLoading && session.error == nil {
                PlayerLoadingView(session: session, title: title)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.isLoading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-player-stage")
    }
}

private struct PlayerLoadingView: View {
    let session: NativePlaybackSession
    let title: Title

    var body: some View {
        ZStack {
            Artwork(url: title.backdropURL(.wide), maxPixel: 900)
                .overlay(Color.black.opacity(0.62))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                ProgressView().controlSize(.large).tint(.white)
                Text(session.phase.message).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if session.isSlow {
                    Text("The server is slow to respond.").font(.footnote).foregroundStyle(.white.opacity(0.75))
                    Button("Try another server", systemImage: "server.rack") { session.openProviderControls() }
                        .buttonStyle(.glass).controlSize(.small)
                }
            }
            .multilineTextAlignment(.center)
            .padding(16)
            .accessibilityElement(children: .contain)
        }
        .clipped()
    }
}

private struct PlayerErrorView: View {
    let session: NativePlaybackSession
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    ContentUnavailableView("Playback unavailable", systemImage: "play.slash", description: Text(session.error ?? ""))
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            Button("Try again", systemImage: "arrow.clockwise", action: retry)
                                .buttonStyle(.glassProminent).foregroundStyle(.black).controlSize(.large)
                            Button("Choose another server", systemImage: "server.rack") { session.openProviderControls() }
                                .buttonStyle(.glass).controlSize(.large)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Chrome

private struct PlayerCloseButton: View {
    let session: NativePlaybackSession
    let close: () -> Void
    private var isTesting: Bool { ProcessInfo.processInfo.environment["CINEJOY_UI_TESTS"] == "1" }

    var body: some View {
        Button("Close player", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityValue(isTesting ? "\(session.diagnostics) captionTracks=\(session.captionTracks.count) captionCues=\(session.captionTracks.reduce(0) { $0 + $1.cues.count })" : "")
    }
}

private struct PlayerSaveButton: View {
    let title: Title
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let saved = library.contains(title)
        Button(saved ? "Remove from Library" : "Save to Library", systemImage: saved ? "bookmark.fill" : "bookmark") { library.toggle(title) }
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .contentTransition(.symbolEffect(.replace))
            .sensoryFeedback(.selection, trigger: saved)
    }
}

private struct PlayerOptionsMenu: View {
    let session: NativePlaybackSession

    var body: some View {
        Menu {
            Picker("Maximum quality", selection: Binding(get: { session.quality }, set: { session.quality = $0 })) {
                ForEach(NativeVideoQuality.allCases) { quality in Text(quality.rawValue).tag(quality) }
            }
            NativeCaptionMenu(tracks: session.captionTracks, selection: Binding(get: { session.selectedCaptionID }, set: { session.selectedCaptionID = $0 }))
            Button("Find subtitles", systemImage: "captions.bubble") { session.openProviderControls(subtitles: true) }
            if session.showProviderControls, session.player != nil {
                Button("Back to video", systemImage: "play.rectangle") { session.returnToNativePlayer() }
            } else {
                Button("Choose server", systemImage: "server.rack") { session.openProviderControls() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Playback options")
    }
}

/// Reads the 1 Hz clock in isolation so only this text updates while playing.
private struct PlayerStatusTitle: View {
    let title: Title
    let episode: EpisodeReference?
    let session: NativePlaybackSession

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.name)
                .font(.headline).lineLimit(1)
                .accessibilityIdentifier("player-status")
                .accessibilityValue("\(session.statusLabel), \(Int(session.seconds)) seconds elapsed")
            Text([episode?.label, session.statusLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlayerTopBar: View {
    let title: Title
    let episode: EpisodeReference?
    let session: NativePlaybackSession
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlayerCloseButton(session: session, close: close)
            PlayerStatusTitle(title: title, episode: episode, session: session)
            if session.showProviderControls, session.player != nil {
                Button("Back to video", systemImage: "play.rectangle.fill") { session.returnToNativePlayer() }
                    .buttonStyle(.glassProminent).foregroundStyle(.black).lineLimit(1)
            } else {
                PlayerFullScreenButton(session: session)
            }
            PlayerOptionsMenu(session: session)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// An always-visible, supported way into AVKit fullscreen. AVKit's inline
/// controls auto-hide, so they cannot be the only route (and are not reliably
/// discoverable by touch or assistive technology).
private struct PlayerFullScreenButton: View {
    let session: NativePlaybackSession

    var body: some View {
        Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { session.enterFullScreen() }
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .disabled(!session.canEnterFullScreen)
            .accessibilityIdentifier("native-fullscreen")
            .accessibilityHint("Plays the video full screen with the system player controls")
    }
}

/// Landscape: controls move to the leading edge, outside the video frame, so the
/// picture uses the full height and never collides with AVKit's own controls.
private struct PlayerRail: View {
    let title: Title
    let session: NativePlaybackSession
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PlayerCloseButton(session: session, close: close)
            Spacer(minLength: 0)
            if session.showProviderControls, session.player != nil {
                Button("Back to video", systemImage: "play.rectangle.fill") { session.returnToNativePlayer() }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle).foregroundStyle(.black)
            } else {
                PlayerFullScreenButton(session: session)
            }
            PlayerOptionsMenu(session: session)
            PlayerSaveButton(title: title)
        }
        .padding(.vertical, 12).padding(.leading, 4).padding(.trailing, 8)
        .background(alignment: .center) { PlayerStatusAccessibility(title: title, session: session) }
    }
}

/// Landscape keeps the same status element for VoiceOver and UI tests.
private struct PlayerStatusAccessibility: View {
    let title: Title
    let session: NativePlaybackSession
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(title.name)
            .accessibilityValue("\(session.statusLabel), \(Int(session.seconds)) seconds elapsed")
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("player-status")
    }
}

// MARK: - Portrait panel

private struct PlayerInfoPanel: View {
    let playback: Playback
    let session: NativePlaybackSession
    let close: () -> Void
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(playback.title.name).font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(metadata).font(.subheadline).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions }
                    VStack(alignment: .leading, spacing: 10) { actions }
                }
                if let episode = playback.episode {
                    PlayerUpNext(title: playback.title, current: episode, currentPath: playback.path, ready: !session.isLoading) { next in
                        session.checkpoint(force: true)
                        library.play(playback.title, path: next.path)
                    }
                } else if !playback.title.overview.isEmpty {
                    Text(playback.title.overview).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("player-info-panel")
    }

    private var metadata: String {
        var parts = [playback.title.year, playback.title.isSeries ? "TV Show" : "Movie"]
        if let episode = playback.episode { parts.insert(episode.label, at: 0) }
        if !playback.title.rating.isEmpty { parts.append("★ \(playback.title.rating)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        let saved = library.contains(playback.title)
        Button { library.toggle(playback.title) } label: {
            Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
        }
        .accessibilityLabel(saved ? "Remove from Library" : "Save to Library")
        .buttonStyle(.glass).contentTransition(.symbolEffect(.replace))
        Menu {
            NativeCaptionMenu(tracks: session.captionTracks, selection: Binding(get: { session.selectedCaptionID }, set: { session.selectedCaptionID = $0 }))
            Button("Find subtitles on the server", systemImage: "magnifyingglass") { session.openProviderControls(subtitles: true) }
        } label: {
            Label("Subtitles", systemImage: session.selectedCaptionID == nil ? "captions.bubble" : "captions.bubble.fill")
        }
        .buttonStyle(.glass)
        Button("Servers", systemImage: "server.rack") { session.openProviderControls() }
            .buttonStyle(.glass)
    }
}

private struct PlayerUpNext: View {
    let title: Title
    let current: EpisodeReference
    let currentPath: String
    let ready: Bool
    let select: (Episode) -> Void
    @Environment(CatalogStore.self) private var catalog
    @State private var episodes: [Episode] = []
    @State private var failed = false

    init(title: Title, current: EpisodeReference, currentPath: String, ready: Bool, select: @escaping (Episode) -> Void) {
        self.title = title
        self.current = current
        self.currentPath = currentPath
        self.ready = ready
        self.select = select
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Season \(current.season)").font(.headline).accessibilityAddTraits(.isHeader)
            if episodes.isEmpty {
                if failed {
                    Text("Episodes for this season aren’t available right now.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(0..<3, id: \.self) { _ in EpisodeRowPlaceholder(compact: true) }
                }
            }
            ForEach(episodes) { episode in
                let playing = episode.path == currentPath
                Button { select(episode) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Artwork(url: .artwork(episode.image, size: .still), maxPixel: 400)
                            .frame(width: 112, height: 63).clipShape(.rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(episode.number). \(episode.name)").font(.subheadline.weight(.semibold)).lineLimit(2)
                            if playing {
                                Label("Now playing", systemImage: "speaker.wave.2.fill").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            } else if !episode.overview.isEmpty {
                                Text(episode.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Not `.disabled`: that dimmed the current episode's title to grey.
                .allowsHitTesting(!playing)
                .accessibilityAddTraits(playing ? .isSelected : [])
                .accessibilityLabel(playing ? "Now playing: episode \(episode.number), \(episode.name)" : "Play episode \(episode.number), \(episode.name)")
            }
        }
        .task(id: ready) { await load() }
    }

    private func load() async {
        if let cached = catalog.cachedEpisodes(for: title, season: current.season) {
            episodes = cached.page.episodes
            if cached.isFresh(6 * 60 * 60) { return }
        }
        // Wait until the video has started: the stream gets the network first.
        guard ready else { return }
        do {
            let page = try await catalog.loadEpisodes(for: title, season: current.season)
            if !page.episodes.isEmpty { episodes = page.episodes }
            failed = episodes.isEmpty
        } catch is CancellationError {
        } catch {
            failed = episodes.isEmpty
        }
    }
}

// MARK: - Session

enum NativeVideoQuality: String, CaseIterable, Identifiable {
    case automatic = "Auto", hd = "Up to 720p", fullHD = "Up to 1080p", ultraHD = "Up to 4K"
    var id: String { rawValue }
    var maximumResolution: CGSize {
        switch self {
        case .automatic: return .zero
        case .hd: return CGSize(width: 1280, height: 720)
        case .fullHD: return CGSize(width: 1920, height: 1080)
        case .ultraHD: return CGSize(width: 3840, height: 2160)
        }
    }
    var maximumBitRate: Double {
        switch self {
        case .automatic: return 0
        case .hd: return 5_000_000
        case .fullHD: return 10_000_000
        case .ultraHD: return 30_000_000
        }
    }
}

@MainActor @Observable final class NativePlaybackSession {
    enum Phase {
        case resolving, starting, ready
        var message: String {
            switch self {
            case .resolving: return "Finding a stream…"
            case .starting: return "Starting video…"
            case .ready: return "Ready"
            }
        }
    }

    private(set) var player: AVPlayer?
    private(set) var seconds = 0.0
    private(set) var captionClock = 0.0
    private(set) var duration = 0.0
    private(set) var path = ""
    private(set) var phase = Phase.resolving
    private(set) var isLoading = true
    /// Set when startup is taking unusually long, so the UI can offer another server
    /// instead of looking hung.
    private(set) var isSlow = false
    private(set) var isPaused = true
    private(set) var isBuffering = false
    private(set) var diagnostics = "Waiting for public player"
    var error: String?
    var showProviderControls = false
    var quality = NativeVideoQuality.automatic { didSet { applyQuality() } }
    private(set) var captionTracks: [CaptionTrack] = []
    var selectedCaptionID: String? {
        didSet {
            // Captions follow the clock immediately instead of waiting for the next tick.
            if selectedCaptionID != nil, let time = player?.currentTime().seconds, time.isFinite { captionClock = time }
        }
    }
    @ObservationIgnored var isFullScreen = false
    @ObservationIgnored var isPictureInPicture = false
    /// The inline AVKit coordinator that can present the same AVPlayer full screen.
    @ObservationIgnored weak var fullScreenPresenter: NativeMoviePlayer.Coordinator?
    /// Identity and fullscreen diagnostics (UI tests compare these across a round trip):
    /// the number of AVPlayer items installed for this session and how the last
    /// fullscreen exit was resolved.
    @ObservationIgnored private(set) var installedItems = 0
    @ObservationIgnored var lastFullScreenExit = "none"
    /// Receives (path, seconds, duration, force). Ticks once per second; the library coalesces.
    @ObservationIgnored var onProgress: (@MainActor (String, Double, Double, Bool) -> Void)?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private let proxy = NativeHLSProxy()
    @ObservationIgnored private var progressObserver: Any?
    @ObservationIgnored private var itemObserver: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObserver: NSKeyValueObservation?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var slowTimer: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastMaster: URL?
    @ObservationIgnored private var resumeSeconds = 0.0
    @ObservationIgnored private var lastDiagnosticTick = -1
    @ObservationIgnored private var startedAt = ContinuousClock.now
    @ObservationIgnored private var stopped = true
    private let audioOwnerID = UUID()
    private static var activeAudioOwner: UUID?
    private static let audioQueue = DispatchQueue(label: "local.cinejoy.audio-session", qos: .userInitiated)

    var statusLabel: String { isLoading ? "Preparing" : isBuffering ? "Buffering" : isPaused ? "Paused" : "Playing" }
    var selectedCaption: CaptionTrack? { captionTracks.first(where: { $0.id == selectedCaptionID }) }
    /// After AVPlayer is ready the hidden website no longer needs to be composited.
    var websiteParked: Bool { player != nil && !isLoading && error == nil && !showProviderControls }
    var canEnterFullScreen: Bool { player != nil && !isLoading && error == nil && !showProviderControls }

    /// Presents the system AVPlayerViewController modally on the same AVPlayer
    /// (supported public API; time, audio and item are shared, nothing restarts).
    func enterFullScreen() {
        guard canEnterFullScreen else { return }
        fullScreenPresenter?.presentFullScreen()
    }

    func prepare(_ playback: Playback, webView: WKWebView) {
        stop()
        stopped = false
        self.webView = webView
        path = playback.path
        resumeSeconds = playback.resumeSeconds
        seconds = 0
        captionClock = 0
        lastDiagnosticTick = -1
        duration = 0
        captionTracks = []
        selectedCaptionID = nil
        error = nil
        showProviderControls = false
        isLoading = true
        isSlow = false
        phase = .resolving
        startedAt = .now
        diagnostics = "Resolving public player"
        loadingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.isLoading else { return }
            self.isLoading = false
            self.error = "The video did not load. Check your connection, or choose another server."
            let phase = String(describing: self.phase)
            Perf.log.error("Player startup timed out in phase \(phase, privacy: .public)")
        }
        slowTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.isLoading, self.error == nil else { return }
            self.isSlow = true
        }
        // Activating the audio session is a synchronous IPC; keep it off the main thread.
        Self.activeAudioOwner = audioOwnerID
        Self.audioQueue.async {
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playback, mode: .moviePlayback)
            try? audio.setActive(true)
        }
    }

    private func elapsedDescription() -> String { (ContinuousClock.now - startedAt).description }

    func receiveMaster(_ url: URL) {
        guard !stopped, url.scheme == "https", let host = url.host?.lowercased(),
              host == "lightspeed.st" || host.hasSuffix(".lightspeed.st"),
              url.lastPathComponent.lowercased() == "master.m3u8", url != lastMaster else { return }
        lastMaster = url
        let requestID = UUID()
        generation = requestID
        streamTask?.cancel()
        isLoading = true
        phase = .starting
        error = nil
        diagnostics = "Public HLS master received; preparing native playback"
        let elapsed = elapsedDescription()
        Perf.log.info("Player master received after \(elapsed, privacy: .public)")
        // The stream is known: stop the hidden website from decoding and playing
        // audio while AVPlayer starts on the same network connection.
        pauseWebsitePlayer()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let localURL = try await self.proxy.start(masterURL: url)
                guard !Task.isCancelled, requestID == self.generation else { return }
                self.installPlayer(url: localURL, requestID: requestID)
            } catch {
                guard !Task.isCancelled, requestID == self.generation else { return }
                self.isLoading = false
                self.error = "This server could not start the video. Choose another server, or try again."
                let failure = error as NSError
                self.diagnostics = "Native transport error \(failure.domain):\(failure.code)"
            }
        }
    }

    private func installPlayer(url: URL, requestID: UUID) {
        removePlayerObservers()
        player?.pause()
        let item = AVPlayerItem(url: url)
        installedItems += 1
        // Start on the first listed variant rather than probing; ABR adapts after.
        item.startsOnFirstEligibleVariant = true
        let native = AVPlayer(playerItem: item)
        native.allowsExternalPlayback = false
        native.usesExternalPlaybackWhileExternalScreenIsActive = false
        native.automaticallyWaitsToMinimizeStalling = true
        player = native
        applyQuality()
        showProviderControls = false
        timeControlObserver = native.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] native, _ in
            let status = native.timeControlStatus
            Task { @MainActor in
                guard let self, requestID == self.generation else { return }
                let wasPlaying = !self.isPaused
                self.isPaused = status == .paused
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                // A pause is a natural moment to store the exact position.
                if wasPlaying, status == .paused { self.checkpoint(force: true) }
            }
        }
        progressObserver = native.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, requestID == self.generation else { return }
                self.tick(time.seconds, item: item, native: native)
            }
        }
        itemObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, requestID == self.generation else { return }
                switch item.status {
                case .readyToPlay:
                    guard self.isLoading else { return }
                    self.loadingTimeout?.cancel()
                    self.slowTimer?.cancel()
                    self.isLoading = false
                    self.isSlow = false
                    self.phase = .ready
                    self.error = nil
                    self.pauseWebsitePlayer()
                    let elapsed = self.elapsedDescription()
                    Perf.log.info("Player ready after \(elapsed, privacy: .public)")
                    let length = item.duration.seconds
                    if length.isFinite, length > 0 { self.duration = length }
                    let seek = self.resumeSeconds
                    self.resumeSeconds = 0
                    if seek > 0, !length.isFinite || seek < length - 20 {
                        native.seek(to: CMTime(seconds: seek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            Task { @MainActor [weak self] in
                                guard let self, requestID == self.generation else { return }
                                native.play()
                            }
                        }
                    } else { native.play() }
                case .failed:
                    self.loadingTimeout?.cancel()
                    self.slowTimer?.cancel()
                    self.isLoading = false
                    self.error = "This server could not play the video. Choose another server, or try again."
                    let failure = item.error as NSError?
                    self.diagnostics = "AVPlayer failed \(failure?.domain ?? "unknown"):\(failure?.code ?? 0)"
                default: break
                }
            }
        }
    }

    #if DEBUG
    /// Uses the production AVPlayer observer/overlay path with a local QA movie.
    /// The fixture is generated only by the focused Simulator job.
    func prepareCaptionQA(url: URL) {
        stop()
        stopped = false
        generation = UUID()
        isLoading = true
        installPlayer(url: url, requestID: generation)
    }
    #endif

    private func tick(_ elapsed: Double, item: AVPlayerItem, native: AVPlayer) {
        let length = item.duration.seconds
        if length.isFinite, length > 0, length != duration { duration = length }
        guard elapsed.isFinite, elapsed >= 0 else { return }
        // Only the caption layer reads this 10 Hz value, and only while a track is on.
        if selectedCaptionID != nil { captionClock = elapsed }
        guard Int(elapsed) != Int(seconds) else { return }
        seconds = elapsed
        onProgress?(path, elapsed, duration, false)
        let second = Int(Date.timeIntervalSinceReferenceDate)
        if second != lastDiagnosticTick, item.status != .failed {
            lastDiagnosticTick = second
            refreshDiagnostics()
        }
    }

    /// Also called on presentation changes: the periodic observer stops while paused,
    /// so state such as `fullscreen=` must not wait for the next playing tick.
    func refreshDiagnostics() {
        guard let native = player, let item = native.currentItem else { return }
        diagnostics = "AVPlayer status=\(item.status.rawValue) control=\(native.timeControlStatus.rawValue) time=\(Int(native.currentTime().seconds.isFinite ? native.currentTime().seconds : seconds)) duration=\(Int(duration)) path=\(path) external=\(native.isExternalPlaybackActive) fullscreen=\(isFullScreen) pip=\(isPictureInPicture) session=\(audioOwnerID.uuidString.prefix(8)) items=\(installedItems) fsExit=\(lastFullScreenExit)"
    }

    /// Stores the exact current position (close, pause, background, episode change).
    func checkpoint(force: Bool) {
        guard let player else { return }
        let time = player.currentTime().seconds
        guard time.isFinite, time > 0, duration > 0 else { return }
        onProgress?(path, time, duration, force)
    }

    /// AVKit returns from fullscreen with playback state intact on current systems;
    /// this only restores it if a transition left a playing video paused.
    func resumeAfterPresentation(wasPlaying: Bool) {
        guard wasPlaying, let player, player.currentItem?.status == .readyToPlay,
              player.timeControlStatus == .paused, !showProviderControls else { return }
        player.play()
    }

    private func applyQuality() {
        player?.currentItem?.preferredMaximumResolution = quality.maximumResolution
        player?.currentItem?.preferredPeakBitRate = quality.maximumBitRate
    }

    func receiveCaptions(_ body: Any) {
        guard let tracks = CaptionTrack.decodeMessage(body) else { return }
        guard tracks != captionTracks else { return }
        captionTracks = tracks
        if !tracks.contains(where: { $0.id == selectedCaptionID }) { selectedCaptionID = nil }
    }

    func openProviderControls(subtitles: Bool = false) {
        player?.pause()
        showProviderControls = true
        webView?.isHidden = false
        webView?.evaluateJavaScript("window.__cinejoyNativeTakeover=false;document.querySelectorAll('video').forEach(v=>{v.muted=false})", completionHandler: nil)
        if subtitles {
            webView?.evaluateJavaScript("document.querySelector('button[aria-label=\"Subtitles\"]')?.click()", completionHandler: nil)
        }
    }

    func returnToNativePlayer() {
        showProviderControls = false
        pauseWebsitePlayer()
        if player?.currentItem?.status == .readyToPlay { player?.play() }
    }

    private func pauseWebsitePlayer() {
        webView?.evaluateJavaScript("window.__cinejoyNativeTakeover=true;document.querySelectorAll('video').forEach(v=>{v.muted=true;v.pause()})", completionHandler: nil)
    }

    func webFailed(_ failure: Error) {
        guard player == nil, (failure as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        error = "Check your connection, or try opening this video again."
        let detail = failure as NSError
        diagnostics = "Public player error \(detail.domain):\(detail.code)"
    }

    func webTerminated() {
        guard player == nil else { return }
        isLoading = false
        error = "The player stopped. Try opening it again."
    }

    private func removePlayerObservers() {
        itemObserver?.invalidate()
        itemObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let progressObserver, let player { player.removeTimeObserver(progressObserver) }
        progressObserver = nil
    }

    func stop() {
        let wasRunning = !stopped
        stopped = true
        generation = UUID()
        streamTask?.cancel()
        streamTask = nil
        loadingTimeout?.cancel()
        loadingTimeout = nil
        slowTimer?.cancel()
        slowTimer = nil
        removePlayerObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        proxy.stop()
        lastMaster = nil
        isPaused = true
        isBuffering = false
        isFullScreen = false
        isPictureInPicture = false
        // SwiftUI may mount the next episode before dismantling the previous
        // resolver. Its late cleanup must not deactivate the new audio session.
        guard wasRunning, Self.activeAudioOwner == audioOwnerID else { return }
        Self.activeAudioOwner = nil
        Self.audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - AVKit

struct NativeMoviePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let session: NativePlaybackSession
    /// The caption host is mounted only while a caption track is selected, so no
    /// extra hosting view sits inside AVKit's overlay during normal playback.
    var captionsActive = false

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.view.backgroundColor = .black
        controller.view.accessibilityIdentifier = "native-inline-player"
        context.coordinator.inline = controller
        session.fullScreenPresenter = context.coordinator
        context.coordinator.setCaptions(active: captionsActive)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        let coordinator = context.coordinator
        // While the fullscreen controller owns the player, the inline one stays empty.
        if !coordinator.isPresentingFullScreen, controller.player !== player { controller.player = player }
        coordinator.setCaptions(active: captionsActive)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.tearDown()
        controller.delegate = nil
        controller.player = nil
    }

    @MainActor final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate {
        let session: NativePlaybackSession
        weak var inline: AVPlayerViewController?
        private var inlineCaptions: UIHostingController<NativeCaptionLayer>?
        /// The app-owned fullscreen container (its child is a system AVPlayerViewController).
        private var fullScreen: NativeFullScreenContainer?
        private var fullScreenCaptions: UIHostingController<NativeCaptionLayer>?
        private var captionsActive = false

        init(session: NativePlaybackSession) { self.session = session }

        var isPresentingFullScreen: Bool { fullScreen != nil }

        // MARK: Captions

        /// Captions live in AVKit's content overlay (between the video and its
        /// controls), so they travel with the video into fullscreen.
        private func makeCaptionHost(in controller: AVPlayerViewController) -> UIHostingController<NativeCaptionLayer>? {
            guard let overlay = controller.contentOverlayView else { return nil }
            let host = UIHostingController(rootView: NativeCaptionLayer(session: session))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            // Caption text must remain readable by VoiceOver. The overlay itself
            // ignores touches, so it never intercepts AVKit controls.
            host.view.accessibilityElementsHidden = false
            host.safeAreaRegions = []
            host.view.frame = overlay.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(host.view)
            return host
        }

        func setCaptions(active: Bool) {
            captionsActive = active
            if active {
                if inlineCaptions == nil, let inline { inlineCaptions = makeCaptionHost(in: inline) }
                if fullScreenCaptions == nil, let fullScreen { fullScreenCaptions = makeCaptionHost(in: fullScreen.playerController) }
            } else {
                inlineCaptions?.view.removeFromSuperview(); inlineCaptions = nil
                fullScreenCaptions?.view.removeFromSuperview(); fullScreenCaptions = nil
            }
        }

        // MARK: Fullscreen (app-owned container embedding the system player)

        func presentFullScreen() {
            guard fullScreen == nil, let inline, inline.viewIfLoaded?.window != nil,
                  inline.presentedViewController == nil, let player = inline.player ?? session.player else { return }
            let child = AVPlayerViewController()
            child.delegate = self
            child.showsPlaybackControls = true
            child.videoGravity = .resizeAspect
            child.allowsPictureInPicturePlayback = true
            child.canStartPictureInPictureAutomaticallyFromInline = true
            child.entersFullScreenWhenPlaybackBegins = false
            child.exitsFullScreenWhenPlaybackEnds = false
            child.view.backgroundColor = .black
            let container = NativeFullScreenContainer(playerController: child) { [weak self] container in
                self?.closeFullScreen(container)
            }
            container.dismissedWithoutOwner = { [weak self] container in
                // Not expected (the app owns dismissal); keep the player consistent anyway.
                guard let self else { return }
                let player = container.playerController.player ?? self.session.player
                self.handBack(container, player: player, playing: player.map { $0.timeControlStatus != .paused } ?? false)
            }
            let wasPlaying = player.timeControlStatus != .paused
            // One AVPlayer, moved between two system controllers: no new item,
            // no seek, no second decode. Only one layer shows the picture.
            inline.player = nil
            child.player = player
            fullScreen = container
            if captionsActive { fullScreenCaptions = makeCaptionHost(in: child) }
            session.isFullScreen = true
            session.refreshDiagnostics()
            Perf.log.info("Native fullscreen: present (playing=\(wasPlaying))")
            inline.present(container, animated: true) {
                // Moving the player between layers must not change its state.
                if wasPlaying, player.timeControlStatus == .paused { player.play() }
            }
        }

        /// The return control's action. The player's actual state is read *before*
        /// anything is dismissed, so it is exactly the user's state, however quickly
        /// they paused before returning.
        private func closeFullScreen(_ container: NativeFullScreenContainer) {
            guard fullScreen === container, !container.isBeingDismissed, !container.closedByOwner else { return }
            let player = container.playerController.player ?? session.player
            let playing = player.map { $0.timeControlStatus != .paused } ?? false
            container.beginOwnerClose()
            container.dismiss(animated: true) { [weak self] in
                MainActor.assumeIsolated { self?.handBack(container, player: player, playing: playing) }
            }
        }

        /// Reattaches the same AVPlayer (same item, same time) inline and restores the
        /// sampled play/pause state exactly.
        private func handBack(_ container: NativeFullScreenContainer, player sampled: AVPlayer?, playing: Bool) {
            guard fullScreen === container else { return }
            fullScreen = nil
            fullScreenCaptions?.view.removeFromSuperview(); fullScreenCaptions = nil
            container.playerController.player = nil
            container.playerController.delegate = nil
            let player = sampled ?? session.player
            if let player, let inline, inline.player !== player { inline.player = player }
            session.isFullScreen = false
            if playing {
                session.resumeAfterPresentation(wasPlaying: true)
            } else if let player, player.timeControlStatus != .paused {
                player.pause()
            }
            session.lastFullScreenExit = playing ? "resumed" : "kept-paused"
            session.refreshDiagnostics()
            Perf.log.info("Native fullscreen: returned inline (playing=\(playing))")
        }

        func tearDown() {
            setCaptions(active: false)
            if let container = fullScreen {
                fullScreen = nil
                container.beginOwnerClose()
                container.playerController.player = nil
                container.playerController.delegate = nil
                if container.presentingViewController != nil { container.dismiss(animated: false) }
            }
            if session.fullScreenPresenter === self { session.fullScreenPresenter = nil }
        }

        // MARK: AVPlayerViewControllerDelegate

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            session.isFullScreen = true
            Perf.log.info("AVKit fullscreen: begin")
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            // AVKit's own fullscreen route (from the inline player, or from the child inside
            // the app's container). The app's container stays up in the latter case.
            let wasPlaying = playerViewController.player?.timeControlStatus != .paused
            let session = self.session
            let insideContainer = playerViewController === fullScreen?.playerController
            coordinator.animate(alongsideTransition: nil) { context in
                guard !context.isCancelled else { return }
                MainActor.assumeIsolated {
                    if !insideContainer { session.isFullScreen = false }
                    session.resumeAfterPresentation(wasPlaying: wasPlaying)
                    Perf.log.info("AVKit fullscreen: end, resumed=\(wasPlaying)")
                }
            }
        }

        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            session.isPictureInPicture = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            session.isPictureInPicture = false
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            // The inline player (or the fullscreen one) is still presented.
            completionHandler(true)
        }
    }
}

/// SwiftUI owns this container's frame and alpha; the app owns the web view inside
/// it. Hiding, touch handling and accessibility of the hidden public page are set
/// here in UIKit, where SwiftUI does not reset them. (Toggling `isHidden` on the
/// representable's own root view did not stick: the native QA hierarchy still showed
/// the website's focused player controls behind the native video.)
final class ResolverContainer: UIView {
    let webView: WKWebView
    var interactive = false { didSet { if interactive != oldValue { apply() } } }
    var parked = false { didSet { if parked != oldValue { apply() } } }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: webView.frame)
        backgroundColor = .clear
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The hidden page never receives touches unless provider controls are shown.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        interactive ? super.hitTest(point, with: event) : nil
    }

    private func apply() {
        webView.isHidden = parked && !interactive
        webView.isUserInteractionEnabled = interactive
        webView.accessibilityElementsHidden = !interactive
        accessibilityElementsHidden = !interactive
        accessibilityElements = interactive ? nil : [Any]()
        if !interactive { webView.endEditing(true) }
    }
}

struct PlaybackResolverView: UIViewRepresentable {
    let playback: Playback
    let session: NativePlaybackSession
    var parked = false
    var interactive = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ResolverContainer {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "stream")
        configuration.userContentController.add(context.coordinator, name: "watch")
        configuration.userContentController.add(context.coordinator, name: "captions")
        for resource in ["PlayerStreamObserver", "PlayerEnvironment"] {
            if let url = Bundle.main.url(forResource: resource, withExtension: "js"),
               let source = try? String(contentsOf: url, encoding: .utf8) {
                configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        if let url = Bundle.main.url(forResource: "NativeCaptionObserver", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if let url = Bundle.main.url(forResource: "PlayerIntegration", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: source.replacingOccurrences(of: "__RESUME_SECONDS__", with: "0"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 430, height: 932), configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        let container = ResolverContainer(webView: view)
        container.interactive = interactive
        container.parked = parked
        session.prepare(playback, webView: view)
        view.load(URLRequest(url: URL(string: "https://cinejoy.pk\(playback.path)")!))
        return container
    }

    func updateUIView(_ container: ResolverContainer, context: Context) {
        context.coordinator.owner = self
        container.interactive = interactive
        container.parked = parked
    }

    static func dismantleUIView(_ container: ResolverContainer, coordinator: Coordinator) {
        let view = container.webView
        view.configuration.userContentController.removeScriptMessageHandler(forName: "stream")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "watch")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "captions")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        if coordinator.owner.session.webView === view {
            coordinator.owner.session.webView = nil
            coordinator.owner.session.checkpoint(force: true)
            coordinator.owner.session.stop()
        }
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var owner: PlaybackResolverView
        init(_ owner: PlaybackResolverView) { self.owner = owner }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { owner.session.webFailed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { owner.session.webFailed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { owner.session.webTerminated() }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "cinejoy.pk" else { return }
            if message.name == "stream", let value = message.body as? String, let url = URL(string: value) {
                owner.session.receiveMaster(url)
            } else if message.name == "captions" {
                owner.session.receiveCaptions(message.body)
            }
            // Website progress deliberately does not feed native history.
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            let sameSite = url.scheme == "https" && url.host == "cinejoy.pk"
            if url.scheme == "about" || (sameSite && (url.path.hasPrefix("/watch/") || action.navigationType != .linkActivated)) {
                decisionHandler(.allow)
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
