import Foundation
import Observation

@MainActor @Observable final class LibraryStore {
    private(set) var saved: [Title] = []
    private(set) var history: [WatchEntry] = []
    var playback: Playback?
    var selectedTab = 0
    var showSettings = false
    private let file: URL
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    // One serial queue keeps atomic writes ordered and off the main thread.
    private let writer = DispatchQueue(label: "local.cinejoy.library-writer", qos: .utility)

    /// Playback reports every second; history (and every view reading it) only
    /// changes when the position moved this far, or on an explicit checkpoint.
    static let checkpointInterval: Double = 10

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Cinejoy", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "library.json")
        // A small local file needed for the first frame (resume accessory).
        if let data = try? Data(contentsOf: file), let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            saved = payload.saved
            history = payload.history
        }
    }

    func contains(_ title: Title) -> Bool { saved.contains { $0.id == title.id } }

    func entry(for title: Title) -> WatchEntry? { history.first { $0.id == title.id } }

    func toggle(_ title: Title) {
        if contains(title) { saved.removeAll { $0.id == title.id } }
        else { saved.insert(title, at: 0) }
        persist(immediately: true)
    }

    func play(_ title: Title, path: String? = nil) {
        let previous = history.first { $0.id == title.id }
        let destination = path ?? previous?.path ?? title.watchPath
        let resume = previous?.path == destination && (previous?.fraction ?? 0) < 0.95 ? previous?.seconds ?? 0 : 0
        playback = Playback(title: title, path: destination, resumeSeconds: resume)
    }

    /// Records a playback position. Routine ticks are coalesced so the UI and
    /// disk are not touched every second; `force` stores the exact position
    /// (closing the player, backgrounding, pausing).
    func record(_ title: Title, path: String, seconds: Double, duration: Double, force: Bool = false) {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration > 0 else { return }
        let existing = history.first { $0.id == title.id }
        guard seconds >= 1 || existing != nil else { return }
        if !force, let existing, existing.path == path, history.first?.id == title.id,
           abs(existing.seconds - seconds) < Self.checkpointInterval, abs(existing.duration - duration) < 1 {
            return
        }
        if let existing, existing.path == path, existing.seconds == seconds, existing.duration == duration { return }
        var next = history
        next.removeAll { $0.id == title.id }
        next.insert(WatchEntry(title: title, path: path, seconds: seconds, duration: duration, updated: .now), at: 0)
        if next.count > 100 { next = Array(next.prefix(100)) }
        history = next
        persist(immediately: force)
    }

    func removeHistory(_ entry: WatchEntry) {
        history.removeAll { $0.id == entry.id }
        persist(immediately: true)
    }

    func clearHistory() { history = []; persist(immediately: true) }

    /// Writes any pending change now (for example when the app moves to the background).
    func flush() { persist(immediately: true) }

    private func persist(immediately: Bool) {
        pendingWrite?.cancel()
        if immediately { write(); return }
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        pendingWrite = nil
        guard let data = try? JSONEncoder().encode(Payload(saved: saved, history: history)) else { return }
        let file = self.file
        writer.async { try? data.write(to: file, options: .atomic) }
    }

    private struct Payload: Codable { var saved: [Title]; var history: [WatchEntry] }
}
