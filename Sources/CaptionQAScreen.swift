#if DEBUG
import SwiftUI
import AVKit

/// Deterministic renderer check. This is deliberately separate from live-provider
/// verification and is never included in the release application's executable.
struct CaptionQAScreen: View {
    @State private var session = NativePlaybackSession()

    var body: some View {
        VStack(spacing: 20) {
            Text("Subtitle renderer QA").font(.headline)
            if let player = session.player {
                NativeMoviePlayer(player: player, session: session, captionsActive: session.selectedCaptionID != nil)
                    .frame(height: 230)
            }
            NativeCaptionMenu(tracks: session.captionTracks, selection: Binding(
                get: { session.selectedCaptionID }, set: { session.selectedCaptionID = $0 }))
            Button("Full Screen") { session.enterFullScreen() }
                .disabled(!session.canEnterFullScreen)
            Button("Pause and seek") {
                session.player?.pause()
                session.player?.seek(to: CMTime(seconds: 15, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            Button("First cue") {
                session.player?.pause()
                session.player?.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            Button("Resume") { session.player?.play() }
            Text(session.statusLabel).accessibilityIdentifier("caption-qa-status")
            Text(String(format: "%.1f", session.captionClock)).accessibilityIdentifier("caption-qa-clock")
            Text("Local test video and synthetic cues; no live provider claim.").font(.caption)
        }
        .padding().preferredColorScheme(.dark)
        .task {
            guard let url = Bundle.main.url(forResource: "CaptionQAFixture", withExtension: "mp4") else { return }
            session.prepareCaptionQA(url: url)
            session.receiveCaptions(["tracks": [["id": "qa-en", "label": "English QA", "language": "en", "cues": [
                ["start": 0, "end": 12, "text": "<i>First caption</i> &amp; timing"],
                ["start": 12, "end": 60, "text": "Second caption\nPaused seek works"]
            ]]]])
        }
        .onDisappear { if !session.isFullScreen { session.stop() } }
    }
}
#endif
