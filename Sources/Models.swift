import Foundation

/// TMDB serves fixed renditions. Request the one that matches how large the
/// artwork is drawn instead of decoding w500/w1280 originals for thumbnails.
enum ArtworkSize: String, Sendable {
    case thumbnail = "w185", poster = "w342", still = "w300", wide = "w780", hero = "w1280"
}

extension URL {
    static func artwork(_ value: String, size: ArtworkSize) -> URL? {
        guard !value.isEmpty else { return nil }
        let sized = value.replacingOccurrences(of: #"/t/p/(?:w\d+|original)/"#, with: "/t/p/\(size.rawValue)/", options: .regularExpression)
        return URL(string: sized)
    }
}

struct Title: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(kind):\(tmdbID)" }
    var tmdbID: Int
    var kind: String
    var name: String
    var year: String = ""
    var poster: String = ""
    var backdrop: String = ""
    var overview: String = ""
    var rating: String = ""
    var path: String
    var isSeries: Bool { kind == "tv" }
    var imageURL: URL? { URL(string: poster) }
    var heroURL: URL? { URL(string: backdrop.isEmpty ? poster : backdrop) }
    func posterURL(_ size: ArtworkSize = .poster) -> URL? { .artwork(poster, size: size) }
    func backdropURL(_ size: ArtworkSize = .wide) -> URL? { .artwork(backdrop.isEmpty ? poster : backdrop, size: size) }
    /// True when the page offered real wide artwork rather than the poster again.
    var hasWideArtwork: Bool {
        guard !backdrop.isEmpty else { return false }
        return URL(string: backdrop)?.lastPathComponent != URL(string: poster)?.lastPathComponent
    }
    var siteURL: URL { URL(string: "https://cinejoy.pk\(path)")! }
    var watchPath: String { isSeries ? "/watch/tv/\(tmdbID)/1/1" : "/watch/movie/\(tmdbID)" }
}

struct Shelf: Codable, Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var titles: [Title]
}

struct Episode: Codable, Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var number: String
    var overview: String
    var image: String
    var path: String
}

struct CatalogPage: Codable, Sendable, Equatable {
    var titles: [Title] = []
    var shelves: [Shelf] = []
    var episodes: [Episode] = []
    var seasons: [Int] = []
}

/// Season and episode numbers read from a public `/watch/tv/{id}/{season}/{episode}` path.
struct EpisodeReference: Equatable, Sendable {
    let season: Int
    let episode: Int
    init?(path: String) {
        let parts = path.split(separator: "/")
        guard parts.count >= 5, parts[0] == "watch", parts[1] == "tv",
              let season = Int(parts[3]), let episode = Int(parts[4]) else { return nil }
        self.season = season
        self.episode = episode
    }
    var label: String { "S\(season) · E\(episode)" }
}

struct WatchEntry: Codable, Identifiable, Sendable {
    var id: String { title.id }
    var title: Title
    var path: String
    var seconds: Double
    var duration: Double
    var updated: Date
    var fraction: Double { duration > 0 ? min(max(seconds / duration, 0), 1) : 0 }
    var episode: EpisodeReference? { EpisodeReference(path: path) }
    var remaining: String {
        guard duration > 0 else { return "Ready to watch" }
        let minutes = max(1, Int((duration - seconds) / 60))
        let time = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min left" : "\(minutes) min left"
        if let episode { return "\(episode.label) · \(time)" }
        return time
    }
}

struct Playback: Identifiable {
    let id = UUID()
    let title: Title
    let path: String
    var resumeSeconds: Double = 0
    var episode: EpisodeReference? { EpisodeReference(path: path) }
}

struct SupplementalInfo: Decodable, Sendable {
    var description: String?
    var runtime: Int?
    var imdb_rating: String?
    var quality_tag_new: String?
    var content_rating: String?
}
