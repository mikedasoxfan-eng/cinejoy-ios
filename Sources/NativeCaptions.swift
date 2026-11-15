import Foundation
import SwiftUI

struct CaptionCue: Decodable, Equatable {
    let start: Double
    let end: Double
    let text: String

    var displayText: String {
        var result = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CaptionTrack: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let language: String
    let cues: [CaptionCue]
    private let prefixEnd: [Double]

    private enum CodingKeys: String, CodingKey { case id, label, language, cues }

    init(id: String, label: String, language: String = "", cues: [CaptionCue]) {
        self.id = id
        self.label = label
        self.language = language
        self.cues = cues.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && !$0.text.isEmpty }
            .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var maximum = -Double.infinity
        self.prefixEnd = self.cues.map { cue in
            maximum = max(maximum, cue.end)
            return maximum
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id),
                  label: try values.decode(String.self, forKey: .label),
                  language: try values.decodeIfPresent(String.self, forKey: .language) ?? "",
                  cues: try values.decode([CaptionCue].self, forKey: .cues))
    }

    static func decodeMessage(_ body: Any) -> [CaptionTrack]? {
        struct Message: Decodable { let tracks: [CaptionTrack] }
        guard let object = body as? [String: Any],
              let rawTracks = object["tracks"] as? [[String: Any]],
              rawTracks.reduce(0, { $0 + (($1["cues"] as? [Any])?.count ?? 0) }) <= 20_000,
              JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 1_000_000,
              let message = try? JSONDecoder().decode(Message.self, from: data),
              message.tracks.reduce(0, { $0 + $1.cues.count }) <= 20_000,
              Set(message.tracks.map(\.id)).count == message.tracks.count else { return nil }
        return message.tracks.filter { !$0.id.isEmpty && !$0.cues.isEmpty }
    }

    func text(at clock: Double) -> String? {
        guard clock.isFinite, !cues.isEmpty else { return nil }
        // Upper bound finds the last cue that could have started. Prefix maximum
        // ends also preserve overlapping cues when a shorter later cue has ended.
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if cues[middle].start <= clock { lower = middle + 1 } else { upper = middle }
        }
        var index = lower - 1
        var active: [String] = []
        while index >= 0 && prefixEnd[index] > clock {
            let cue = cues[index]
            if cue.start <= clock && clock < cue.end {
                let text = cue.displayText
                if !text.isEmpty && !active.contains(text) { active.append(text) }
            }
            index -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }
}

struct NativeCaptionOverlay: View {
    let clock: Double
    let track: CaptionTrack?
    var font: Font = .title3.weight(.semibold)
    var bottomInset: CGFloat = 64

    var body: some View {
        VStack {
            Spacer()
            if let text = track?.text(at: clock) {
                Text(verbatim: text)
                    .font(font)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.78), in: .rect(cornerRadius: 8))
                    .padding(.horizontal, 24).padding(.bottom, bottomInset)
                    .accessibilityIdentifier("native-caption-text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Hosted inside AVPlayerViewController.contentOverlayView, so captions follow the
/// video into AVKit fullscreen. Text scales with the picture width and Dynamic Type.
/// This is the only view that reads the 10 Hz caption clock.
struct NativeCaptionLayer: View {
    let session: NativePlaybackSession
    @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 16

    init(session: NativePlaybackSession) { self.session = session }

    var body: some View {
        GeometryReader { geometry in
            if let track = session.selectedCaption {
                // AVKit's overlay fills the whole controller, including portrait
                // letterboxing. Keep cues on the fitted video picture itself.
                let source = session.player?.currentItem?.presentationSize ?? .zero
                let fit = source.width > 0 && source.height > 0
                    ? min(geometry.size.width / source.width, geometry.size.height / source.height) : 1
                let picture = source.width > 0 && source.height > 0
                    ? CGSize(width: source.width * fit, height: source.height * fit) : geometry.size
                let scale = min(max(picture.width / 393, 1), 1.7)
                NativeCaptionOverlay(clock: session.captionClock, track: track,
                                     font: .system(size: baseSize * scale, weight: .semibold),
                                     bottomInset: max(20, picture.height * 0.12))
                    .frame(width: picture.width, height: picture.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(session.selectedCaption == nil)
    }
}

struct NativeCaptionMenu: View {
    let tracks: [CaptionTrack]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button { selection = nil } label: {
                if selection == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(tracks) { track in
                Button { selection = track.id } label: {
                    if selection == track.id { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                }
            }
        } label: {
            Label("Subtitles", systemImage: selection == nil ? "captions.bubble" : "captions.bubble.fill")
        }
        .accessibilityLabel("Subtitles")
    }
}
