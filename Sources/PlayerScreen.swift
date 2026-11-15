import SwiftUI
import WebKit
import AVFAudio

struct PlayerScreen: View {
    let playback: Playback
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var isLoading = true
    @State private var error: String?
    @State private var attempt = 0
    @State private var seconds = 0.0
    @State private var isPaused = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlaybackWebView(playback: playback, isLoading: $isLoading, error: $error) { path, elapsed, duration, paused in
                seconds = elapsed
                isPaused = paused
                library.record(playback.title, path: path, seconds: elapsed, duration: duration)
            }
            .id(attempt).ignoresSafeArea(edges: .bottom)
            if isLoading && error == nil {
                VStack(spacing: 14) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("Getting \(playback.title.name) ready…").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .padding(24).glassEffect(in: .rect(cornerRadius: 24))
            }
            if let error {
                VStack(spacing: 18) {
                    ContentUnavailableView("Playback unavailable", systemImage: "play.slash", description: Text(error))
                    Button("Try again", systemImage: "arrow.clockwise") {
                        self.error = nil; isLoading = true; attempt += 1
                    }.buttonStyle(.glassProminent).foregroundStyle(.black)
                }.padding(24)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button("Close player", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Spacer()
                Text(playback.title.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 16).padding(.vertical, 12).glassEffect()
                    .accessibilityIdentifier("player-status")
                    .accessibilityValue("\(isPaused ? "Paused" : "Playing"), \(Int(seconds)) seconds elapsed")
                Spacer()
                Button(library.contains(playback.title) ? "Remove from Library" : "Save to Library",
                       systemImage: library.contains(playback.title) ? "bookmark.fill" : "bookmark") { library.toggle(playback.title) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

struct PlaybackWebView: UIViewRepresentable {
    let playback: Playback
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onProgress: (String, Double, Double, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback)
        try? audio.setActive(true)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "watch")
        if let url = Bundle.main.url(forResource: "PlayerIntegration", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = source.replacingOccurrences(of: "__RESUME_SECONDS__", with: String(playback.resumeSeconds))
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: URL(string: "https://cinejoy.pk\(playback.path)")!))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.owner = self }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "watch")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var owner: PlaybackWebView
        init(_ owner: PlaybackWebView) { self.owner = owner }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { owner.isLoading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            owner.isLoading = false
            owner.error = "The player stopped. Try opening it again."
        }

        private func failed(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            owner.isLoading = false
            owner.error = "Check your connection, or try a different server in the player."
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "watch", message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host == "cinejoy.pk",
                  let value = message.body as? [String: Any],
                  let seconds = value["seconds"] as? Double,
                  let duration = value["duration"] as? Double,
                  let path = value["path"] as? String, path.hasPrefix("/watch/") else { return }
            owner.onProgress(path, seconds, duration, value["paused"] as? Bool ?? true)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            // Provider frames are allowed; top-level navigation stays in the player.
            if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            if url.scheme == "about" || (url.scheme == "https" && url.host == "cinejoy.pk" && url.path.hasPrefix("/watch/")) {
                decisionHandler(.allow)
            } else { decisionHandler(.cancel) }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
