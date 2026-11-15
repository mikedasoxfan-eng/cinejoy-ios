import Foundation
import Observation

@MainActor @Observable final class LibraryStore {
    private(set) var saved: [Title] = []
    private(set) var history: [WatchEntry] = []
    var playback: Playback?
    var selectedTab = 0
    var showSettings = false
    private let file: URL

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Cinejoy", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "library.json")
        if let data = try? Data(contentsOf: file), let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            saved = payload.saved
            history = payload.history
        }
    }

    func contains(_ title: Title) -> Bool { saved.contains { $0.id == title.id } }

    func toggle(_ title: Title) {
        if contains(title) { saved.removeAll { $0.id == title.id } }
        else { saved.insert(title, at: 0) }
        persist()
    }

    func play(_ title: Title, path: String? = nil) {
        let previous = history.first { $0.id == title.id }
        let destination = path ?? previous?.path ?? title.watchPath
        let resume = previous?.path == destination && (previous?.fraction ?? 0) < 0.95 ? previous?.seconds ?? 0 : 0
        playback = Playback(title: title, path: destination, resumeSeconds: resume)
    }

    func record(_ title: Title, path: String, seconds: Double, duration: Double) {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration > 0 else { return }
        guard seconds >= 1 || history.contains(where: { $0.id == title.id }) else { return }
        history.removeAll { $0.id == title.id }
        history.insert(WatchEntry(title: title, path: path, seconds: seconds, duration: duration, updated: .now), at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        persist()
    }

    func removeHistory(_ entry: WatchEntry) {
        history.removeAll { $0.id == entry.id }
        persist()
    }

    func clearHistory() { history = []; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(Payload(saved: saved, history: history)) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private struct Payload: Codable { var saved: [Title]; var history: [WatchEntry] }
}
