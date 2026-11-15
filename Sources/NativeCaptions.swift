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

    var body: some View {
        VStack {
            Spacer()
            if let text = track?.text(at: clock) {
                Text(verbatim: text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.78), in: .rect(cornerRadius: 8))
                    .padding(.horizontal, 24).padding(.bottom, 64)
                    .accessibilityIdentifier("native-caption-text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
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
