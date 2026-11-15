import Foundation

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
    var siteURL: URL { URL(string: "https://cinejoy.pk\(path)")! }
    var watchPath: String { isSeries ? "/watch/tv/\(tmdbID)/1/1" : "/watch/movie/\(tmdbID)" }
}

struct Shelf: Codable, Identifiable, Sendable {
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

struct CatalogPage: Codable, Sendable {
    var titles: [Title] = []
    var shelves: [Shelf] = []
    var episodes: [Episode] = []
    var seasons: [Int] = []
}

struct WatchEntry: Codable, Identifiable, Sendable {
    var id: String { title.id }
    var title: Title
    var path: String
    var seconds: Double
    var duration: Double
    var updated: Date
    var fraction: Double { duration > 0 ? min(max(seconds / duration, 0), 1) : 0 }
    var remaining: String {
        guard duration > 0 else { return "Ready to watch" }
        return "\(max(1, Int((duration - seconds) / 60))) min left"
    }
}

struct Playback: Identifiable {
    let id = UUID()
    let title: Title
    let path: String
    var resumeSeconds: Double = 0
}

struct SupplementalInfo: Decodable, Sendable {
    var description: String?
    var runtime: Int?
    var imdb_rating: String?
    var quality_tag_new: String?
    var content_rating: String?
}
