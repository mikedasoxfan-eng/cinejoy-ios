import SwiftUI
import Observation
import WebKit
import AVKit
import AVFAudio

struct PlayerScreen: View {
    let playback: Playback
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var session = NativePlaybackSession()
    @State private var attempt = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // A real, laid-out page lets the public website resolve its player.
            // The resolver is not extracted or copied into the app.
            PlaybackResolverView(playback: playback, session: session)
                .id(attempt)
                .opacity(session.showProviderControls ? 1 : 0.001)
                .allowsHitTesting(session.showProviderControls)
                .accessibilityHidden(!session.showProviderControls)
                .ignoresSafeArea(edges: .bottom)
            if let player = session.player, !session.showProviderControls {
                NativeMoviePlayer(player: player)
                    .overlay(alignment: .bottom) {
                        NativeCaptionOverlay(clock: session.captionClock, track: session.selectedCaption)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            if session.isLoading && session.error == nil && !session.showProviderControls {
                VStack(spacing: 14) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("Getting \(playback.title.name) ready…")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .padding(24).glassEffect(in: .rect(cornerRadius: 24))
            }
            if let error = session.error, !session.showProviderControls {
                Color.black.ignoresSafeArea()
                VStack(spacing: 18) {
                    ContentUnavailableView("Playback unavailable", systemImage: "play.slash", description: Text(error))
                    Button("Try again", systemImage: "arrow.clockwise") {
                        session.stop()
                        attempt += 1
                    }.buttonStyle(.glassProminent).foregroundStyle(.black)
                    Button("Choose another server", systemImage: "server.rack") { session.openProviderControls() }
                        .buttonStyle(.glass)
                }.padding(24)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Button("Close player", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityValue(isTesting ? session.diagnostics : "")
                Spacer(minLength: 0)
                Text(playback.title.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 16).padding(.vertical, 12).glassEffect()
                    .accessibilityIdentifier("player-status")
                    .accessibilityValue("\(session.statusLabel), \(Int(session.seconds)) seconds elapsed")
                    .accessibilityHint(isTesting ? session.diagnostics : "")
                Spacer(minLength: 0)
                Menu("Playback options", systemImage: "ellipsis") {
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
                }
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                .buttonStyle(.glass).buttonBorderShape(.circle)
                Button(library.contains(playback.title) ? "Remove from Library" : "Save to Library",
                       systemImage: library.contains(playback.title) ? "bookmark.fill" : "bookmark") { library.toggle(playback.title) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .onChange(of: session.seconds) { _, seconds in
            library.record(playback.title, path: session.path, seconds: seconds, duration: session.duration)
        }
        .onDisappear { session.stop() }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    private var isTesting: Bool { ProcessInfo.processInfo.environment["CINEJOY_UI_TESTS"] == "1" }
}

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
    private(set) var player: AVPlayer?
    private(set) var seconds = 0.0
    private(set) var captionClock = 0.0
    private(set) var duration = 0.0
    private(set) var path = ""
    private(set) var isLoading = true
    private(set) var isPaused = true
    private(set) var isBuffering = false
    private(set) var diagnostics = "Waiting for public player"
    var error: String?
    var showProviderControls = false
    var quality = NativeVideoQuality.automatic { didSet { applyQuality() } }
    private(set) var captionTracks: [CaptionTrack] = []
    var selectedCaptionID: String?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private let proxy = NativeHLSProxy()
    @ObservationIgnored private var progressObserver: Any?
    @ObservationIgnored private var itemObserver: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObserver: NSKeyValueObservation?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastMaster: URL?
    @ObservationIgnored private var resumeSeconds = 0.0
    @ObservationIgnored private var lastDiagnosticTick = -1

    var statusLabel: String { isLoading ? "Preparing" : isBuffering ? "Buffering" : isPaused ? "Paused" : "Playing" }
    var selectedCaption: CaptionTrack? { captionTracks.first(where: { $0.id == selectedCaptionID }) }

    func prepare(_ playback: Playback, webView: WKWebView) {
        stop()
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
        diagnostics = "Resolving public player"
        loadingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.isLoading else { return }
            self.isLoading = false
            self.error = "The video did not load. Check your connection, or choose another server."
        }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback)
        try? audio.setActive(true)
    }

    func receiveMaster(_ url: URL) {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              host == "lightspeed.st" || host.hasSuffix(".lightspeed.st"),
              url.lastPathComponent.lowercased() == "master.m3u8", url != lastMaster else { return }
        lastMaster = url
        let requestID = UUID()
        generation = requestID
        streamTask?.cancel()
        isLoading = true
        error = nil
        diagnostics = "Public HLS master received; preparing native playback"
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
        let native = AVPlayer(playerItem: item)
        native.allowsExternalPlayback = false
        native.usesExternalPlaybackWhileExternalScreenIsActive = false
        native.automaticallyWaitsToMinimizeStalling = true
        player = native
        applyQuality()
        showProviderControls = false
        timeControlObserver = native.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] native, _ in
            Task { @MainActor in
                guard let self, requestID == self.generation else { return }
                self.isPaused = native.timeControlStatus == .paused
                self.isBuffering = native.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        progressObserver = native.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, requestID == self.generation else { return }
                let elapsed = time.seconds
                let length = item.duration.seconds
                if length.isFinite, length > 0 { self.duration = length }
                if elapsed.isFinite, elapsed >= 0 {
                    self.captionClock = elapsed
                    // Caption timing follows AVPlayer closely without writing
                    // history or changing its accessibility value ten times/sec.
                    if Int(elapsed) != Int(self.seconds) { self.seconds = elapsed }
                }
                let tick = Int(Date.timeIntervalSinceReferenceDate)
                if tick != self.lastDiagnosticTick, item.status != .failed {
                    self.lastDiagnosticTick = tick
                    self.diagnostics = "AVPlayer status=\(item.status.rawValue) control=\(native.timeControlStatus.rawValue) time=\(Int(self.seconds)) duration=\(Int(self.duration)) external=\(native.isExternalPlaybackActive)"
                }
            }
        }
        itemObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, requestID == self.generation else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadingTimeout?.cancel()
                    self.isLoading = false
                    self.error = nil
                    self.pauseWebsitePlayer()
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
                    self.isLoading = false
                    self.error = "This server could not play the video. Choose another server, or try again."
                    let failure = item.error as NSError?
                    self.diagnostics = "AVPlayer failed \(failure?.domain ?? "unknown"):\(failure?.code ?? 0)"
                default: break
                }
            }
        }
    }

    private func applyQuality() {
        player?.currentItem?.preferredMaximumResolution = quality.maximumResolution
        player?.currentItem?.preferredPeakBitRate = quality.maximumBitRate
    }

    func receiveCaptions(_ body: Any) {
        guard let tracks = CaptionTrack.decodeMessage(body) else { return }
        captionTracks = tracks
        if !tracks.contains(where: { $0.id == selectedCaptionID }) { selectedCaptionID = nil }
    }

    func openProviderControls(subtitles: Bool = false) {
        player?.pause()
        showProviderControls = true
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
        generation = UUID()
        streamTask?.cancel()
        streamTask = nil
        loadingTimeout?.cancel()
        loadingTimeout = nil
        removePlayerObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        proxy.stop()
        lastMaster = nil
        isPaused = true
        isBuffering = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct NativeMoviePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}

struct PlaybackResolverView: UIViewRepresentable {
    let playback: Playback
    let session: NativePlaybackSession
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
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
        session.prepare(playback, webView: view)
        view.load(URLRequest(url: URL(string: "https://cinejoy.pk\(playback.path)")!))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.owner = self }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "stream")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "watch")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "captions")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        if coordinator.owner.session.webView === view {
            coordinator.owner.session.webView = nil
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
