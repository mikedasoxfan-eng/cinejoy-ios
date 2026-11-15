import Foundation
import Observation
import WebKit
import SwiftUI
import os

/// Lightweight measurements. View in Console (subsystem local.cinejoy.glass) or
/// Instruments > Points of Interest/os_signpost to separate network waits from UI work.
enum Perf {
    static let log = Logger(subsystem: "local.cinejoy.glass", category: "performance")
    static let signposts = OSSignposter(subsystem: "local.cinejoy.glass", category: "performance")
}

/// Hidden catalog readers only need the DOM. Blocking images, video and fonts stops
/// each hidden page from downloading and compositing hundreds of posters, blurred
/// ambient art and animated GIFs while the native UI loads the same artwork.
@MainActor enum ReaderRules {
    private static var compiled: WKContentRuleList?
    private static var loading: Task<WKContentRuleList?, Never>?

    static func list() async -> WKContentRuleList? {
        if let compiled { return compiled }
        if let loading { return await loading.value }
        let task = Task { @MainActor () async -> WKContentRuleList? in
            let rules = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
            let list: WKContentRuleList? = try? await WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: "cinejoy-reader-v1", encodedContentRuleList: rules)
            compiled = list
            return list
        }
        loading = task
        return await task.value
    }
}

// Reads the same public pages the user can browse. No copied TMDB credential,
// account token, protected resolver implementation, or private endpoint is needed.
@MainActor final class PageReader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var diagnostic: String?
    private var generation = UUID()
    private var rulesInstalled = false

    /// Loaded once instead of from disk on every poll.
    private static let extraction: String? = Bundle.main.url(forResource: "CatalogExtraction", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        // Hide the announcement and drop the site's blur/backdrop effects: this
        // page is never seen, so it should not pay for glass compositing.
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.addEventListener('DOMContentLoaded',()=>{const s=document.createElement('style');s.textContent='[role=dialog][aria-labelledby=notice-title]{display:none!important}*,*::before,*::after{backdrop-filter:none!important;-webkit-backdrop-filter:none!important;filter:none!important}';document.head.append(s)});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 430, height: 932), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    private func installRules() async {
        guard !rulesInstalled else { return }
        rulesInstalled = true
        if let list = await ReaderRules.list() { webView.configuration.userContentController.add(list) }
    }

    /// A cheap readiness probe: counts title/episode links and closes the site's
    /// announcement. The full extraction only runs once the count is stable.
    private static func probe(search: Bool) -> String {
        """
        (() => {
          for (const d of document.querySelectorAll('[role=dialog]')) {
            if (d.querySelector('h3')?.textContent?.trim() === 'Good news!') d.querySelector('button[aria-label=Close]')?.click();
          }
          const n = document.querySelectorAll('a[href^="/movie/"],a[href^="/series/"],a[href^="/watch/tv/"]').length;
          if (\(search ? "true" : "false")) {
            if ([...document.querySelectorAll('h2')].some(h => h.textContent.trim() === 'Trending Today')) return -1;
            if (n === 0 && /No results|No titles/.test(document.body?.innerText || '')) return -2;
          }
          return n;
        })()
        """
    }

    /// - Parameter stableReads: consecutive identical link counts (250 ms apart) required
    ///   before extracting, so progressively rendered pages are not cut short.
    func read(path: String, season: Int? = nil, stableReads: Int = 2) async throws -> CatalogPage {
        let requestID = UUID()
        diagnostic = nil
        generation = requestID
        let signpostID = Perf.signposts.makeSignpostID()
        let interval = Perf.signposts.beginInterval("PageRead", id: signpostID, "\(path, privacy: .public)")
        let started = ContinuousClock.now
        defer {
            Perf.signposts.endInterval("PageRead", interval)
            if requestID == generation {
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
            }
        }
        await installRules()
        guard var components = URLComponents(string: "https://cinejoy.pk\(path)") else { throw URLError(.badURL) }
        if let season {
            // The public page reads its initial season from this query and writes
            // the same query when its selector changes. Start at the requested
            // season so exact URL validation remains valid after selection.
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "season" }
            items.append(URLQueryItem(name: "season", value: String(season)))
            components.queryItems = items
        }
        guard let url = components.url else { throw URLError(.badURL) }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
        let search = path.hasPrefix("/search") && url.query != nil
        let probe = Self.probe(search: search)
        let matchesSeason: (CatalogPage) -> Bool = { page in
            guard let season else { return true }
            return page.episodes.contains { $0.path.split(separator: "/").dropLast().last == Substring(String(season)) }
        }
        var lastCount = Int.min
        var stable = 0
        var emptyReads = 0
        for _ in 0..<80 {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            guard requestID == generation else { throw CancellationError() }
            guard let current = webView.url, current.path == url.path, current.query == url.query,
                  ContinuousClock.now - started >= .milliseconds(500) else { continue }
            let count = ((try? await webView.evaluateJavaScript(probe)) as? Int) ?? 0
            if count == -2 {
                emptyReads += 1
                if emptyReads >= 2, !webView.isLoading {
                    Perf.log.info("PageRead \(path, privacy: .public) empty after \((ContinuousClock.now - started).description, privacy: .public)")
                    return CatalogPage()
                }
                continue
            }
            emptyReads = 0
            guard count > 0 else { lastCount = count; stable = 0; continue }
            if count == lastCount { stable += 1 } else { lastCount = count; stable = 0 }
            guard stable >= max(0, stableReads - 1) else { continue }
            guard let page = await extract() else { continue }
            if !matchesSeason(page) { stable = 0; continue }
            if !page.titles.isEmpty || !page.episodes.isEmpty {
                Perf.log.info("PageRead \(path, privacy: .public) ready in \((ContinuousClock.now - started).description, privacy: .public): \(page.titles.count) titles, \(page.episodes.count) episodes")
                return page
            }
        }
        // The page kept changing for the whole window: use what it shows now.
        if let page = await extract(), matchesSeason(page), !page.titles.isEmpty || !page.episodes.isEmpty { return page }
        if let season {
            diagnostic = (try? await webView.evaluateJavaScript("JSON.stringify({url:location.href,width:innerWidth,heading:document.querySelector('h2 button')?.textContent,expanded:document.querySelector('h2 button')?.getAttribute('aria-expanded'),dialogs:[...document.querySelectorAll('[role=dialog]')].map(d=>({title:d.querySelector('h3')?.textContent,wheel:!!d.querySelector('.wheel')})),episodes:[...document.links].filter(a=>a.pathname.startsWith('/watch/tv/')).slice(0,3).map(a=>a.pathname)})")) as? String
            let detail = "Expected \(url.absoluteString); \(diagnostic ?? "DOM unavailable")"
            diagnostic = detail
            Perf.log.error("Catalog season \(season) timeout: \(detail, privacy: .public)")
        }
        Perf.log.error("PageRead \(path, privacy: .public) timed out")
        throw URLError(.timedOut)
    }

    private func extract() async -> CatalogPage? {
        guard let script = Self.extraction,
              let text = (try? await webView.evaluateJavaScript(script)) as? String else { return nil }
        let data = Data(text.utf8)
        // Decoding a few hundred titles is moved off the main thread.
        return await Task.detached(priority: .userInitiated) { try? JSONDecoder().decode(CatalogPage.self, from: data) }.value
    }

    func cancel() { generation = UUID(); webView.stopLoading(); webView.loadHTMLString("", baseURL: nil) }
}

/// One in-flight page read shared by every screen asking for the same page.
/// It is cancelled when the last interested screen goes away.
@MainActor private final class PageFlight {
    let task: Task<CatalogPage, Error>
    var waiters = Set<UUID>()
    init(task: Task<CatalogPage, Error>) { self.task = task }
}

struct CachedPage: Codable, Sendable {
    var page: CatalogPage
    var date: Date
    func isFresh(_ lifetime: TimeInterval) -> Bool { Date.now.timeIntervalSince(date) < lifetime }
}

@MainActor @Observable final class CatalogStore {
    private(set) var shelves: [Shelf] = []
    /// Unique titles across shelves, computed once per catalog change rather than per view update.
    private(set) var titles: [Title] = []
    private(set) var isRefreshing = false
    private(set) var error: String?
    private(set) var lastUpdated: Date?

    /// Two hidden readers: a home refresh never blocks a detail or search read,
    /// and neither cancels the other (one shared reader used to do both).
    let readers: [PageReader] = [PageReader(), PageReader()]
    @ObservationIgnored private var idle: [PageReader] = []
    @ObservationIgnored private var flights: [String: PageFlight] = [:]
    @ObservationIgnored private var pages: [String: CachedPage] = [:]
    @ObservationIgnored private var infos: [String: SupplementalInfo] = [:]
    @ObservationIgnored private var infoTasks: [String: Task<SupplementalInfo?, Never>] = [:]
    @ObservationIgnored private var didLoad = false
    private let cacheFile = URL.cachesDirectory.appending(path: "cinejoy-catalog.json")
    private let pageDirectory = URL.cachesDirectory.appending(path: "CinejoyPages", directoryHint: .isDirectory)
    private let diskQueue = DispatchQueue(label: "local.cinejoy.catalog-cache", qos: .utility)

    init() {
        idle = readers
        try? FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
        let sources = [cacheFile, Bundle.main.url(forResource: "CatalogSeed", withExtension: "json")].compactMap { $0 }
        for source in sources {
            if let data = try? Data(contentsOf: source), let page = try? JSONDecoder().decode(CatalogPage.self, from: data), !page.shelves.isEmpty {
                apply(page.shelves)
                if source == cacheFile {
                    lastUpdated = (try? FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date
                }
                break
            }
        }
    }

    private func apply(_ shelves: [Shelf]) {
        self.shelves = shelves
        var ids = Set<String>()
        titles = shelves.flatMap(\.titles).filter { ids.insert($0.id).inserted }
    }

    // MARK: Reader pool

    private func acquire() async throws -> PageReader {
        while true {
            if let reader = idle.popLast() { return reader }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func release(_ reader: PageReader) {
        if !idle.contains(where: { $0 === reader }) { idle.append(reader) }
    }

    /// Coalesced, cancellable page read. Identical concurrent requests share one load.
    private func readPage(key: String, path: String, season: Int? = nil, stableReads: Int = 2) async throws -> CatalogPage {
        let flight: PageFlight
        if let existing = flights[key] {
            flight = existing
        } else {
            let task = Task { @MainActor [weak self] () async throws -> CatalogPage in
                guard let self else { throw CancellationError() }
                let waitStart = ContinuousClock.now
                let reader = try await self.acquire()
                defer { self.release(reader) }
                let queued = ContinuousClock.now - waitStart
                if queued > .milliseconds(300) {
                    Perf.log.info("PageRead \(key, privacy: .public) waited \(queued.description, privacy: .public) for a reader")
                }
                return try await reader.read(path: path, season: season, stableReads: stableReads)
            }
            flight = PageFlight(task: task)
            flights[key] = flight
        }
        let token = UUID()
        flight.waiters.insert(token)
        defer { leave(key, flight, token) }
        return try await withTaskCancellationHandler {
            try await flight.task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.leave(key, flight, token) }
        }
    }

    private func leave(_ key: String, _ flight: PageFlight, _ token: UUID) {
        guard flight.waiters.remove(token) != nil, flight.waiters.isEmpty else { return }
        flight.task.cancel()
        if flights[key] === flight { flights[key] = nil }
    }

    // MARK: Page cache

    private func fileURL(_ key: String) -> URL {
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(key.hashValue)
        return pageDirectory.appending(path: name + ".json")
    }

    func cached(_ key: String) -> CachedPage? {
        if let hit = pages[key] { return hit }
        guard let data = try? Data(contentsOf: fileURL(key)),
              let stored = try? JSONDecoder().decode(CachedPage.self, from: data) else { return nil }
        pages[key] = stored
        return stored
    }

    private func store(_ page: CatalogPage, key: String, disk: Bool) {
        let entry = CachedPage(page: page, date: .now)
        pages[key] = entry
        guard disk else { return }
        let file = fileURL(key)
        diskQueue.async {
            if let data = try? JSONEncoder().encode(entry) { try? data.write(to: file, options: .atomic) }
        }
    }

    // MARK: Episodes

    static func episodesKey(_ title: Title, season: Int) -> String { "\(title.path)#season-\(season)" }

    func cachedEpisodes(for title: Title, season: Int) -> CachedPage? { cached(Self.episodesKey(title, season: season)) }

    func loadEpisodes(for title: Title, season: Int) async throws -> CatalogPage {
        let key = Self.episodesKey(title, season: season)
        let page = try await readPage(key: key, path: title.path, season: season)
        store(page, key: key, disk: true)
        return page
    }

    // MARK: Search

    func search(_ term: String) async throws -> [Title] {
        var components = URLComponents()
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: term)]
        guard let path = components.string else { throw URLError(.badURL) }
        let key = "search:" + term.lowercased()
        if let hit = pages[key], hit.isFresh(10 * 60) { return hit.page.titles }
        let page = try await readPage(key: key, path: path)
        store(page, key: key, disk: false)
        return page.titles
    }

    func localMatches(_ term: String) -> [Title] {
        titles.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    // MARK: Supplemental details

    func cachedInfo(for title: Title) -> SupplementalInfo? { infos[title.id] }

    func info(for title: Title) async -> SupplementalInfo? {
        if let hit = infos[title.id] { return hit }
        if let running = infoTasks[title.id] { return await running.value }
        let task = Task { () async -> SupplementalInfo? in try? await TitleInfoService.info(for: title) }
        infoTasks[title.id] = task
        let value = await task.value
        infoTasks[title.id] = nil
        if let value { infos[title.id] = value }
        return value
    }

    // MARK: Home catalog

    func refresh(force: Bool = false) async {
        guard !isRefreshing, force || !didLoad else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let page = try await readPage(key: "home", path: "/", stableReads: 3)
            var incoming = page.shelves
            if incoming.isEmpty, !page.titles.isEmpty { incoming = [Shelf(name: "Discover", titles: page.titles)] }
            let incomingCount = incoming.reduce(0) { $0 + $1.titles.count }
            // A page caught mid-render must not replace a fuller catalog.
            guard incomingCount >= min(20, titles.count) else {
                Perf.log.info("Home refresh ignored a partial page (\(incomingCount) titles)")
                return
            }
            let merged = await mergeKnownArtwork(into: incoming)
            apply(merged)
            error = nil
            lastUpdated = .now
            didLoad = true
            let snapshot = CatalogPage(titles: [], shelves: merged)
            let file = cacheFile
            diskQueue.async {
                if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
            }
        } catch is CancellationError {} catch {
            self.error = "Couldn’t reach Cinejoy. Showing your saved catalog."
        }
    }

    /// Live cards only carry posters. Keep real wide artwork and descriptions already
    /// known for the same title (bundled snapshot or last catalog) instead of cropping a poster.
    private func mergeKnownArtwork(into shelves: [Shelf]) async -> [Shelf] {
        let current = titles
        return await Task.detached(priority: .utility) { () -> [Shelf] in
            var known: [String: Title] = [:]
            if let url = Bundle.main.url(forResource: "CatalogSeed", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let seed = try? JSONDecoder().decode(CatalogPage.self, from: data) {
                for title in seed.shelves.flatMap(\.titles) { known[title.id] = title }
            }
            for title in current { known[title.id] = title }
            return shelves.map { shelf in
                var shelf = shelf
                shelf.titles = shelf.titles.map { title in
                    var title = title
                    if let previous = known[title.id] {
                        if !title.hasWideArtwork, previous.hasWideArtwork { title.backdrop = previous.backdrop }
                        if title.overview.isEmpty { title.overview = previous.overview }
                        if title.rating.isEmpty { title.rating = previous.rating }
                    }
                    return title
                }
                return shelf
            }
        }.value
    }
}

enum TitleInfoService {
    static func info(for title: Title) async throws -> SupplementalInfo {
        var components = URLComponents(string: "https://api2.wing.st/info")!
        components.queryItems = [URLQueryItem(name: "type", value: title.kind), URLQueryItem(name: "tmdb", value: String(title.tmdbID))]
        var request = URLRequest(url: components.url!, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SupplementalInfo.self, from: data)
    }
}

// WebKit needs a view in the hierarchy for reliable page lifecycle/rendering.
// This inert, inaccessible backing view supplies catalog data to native screens.
struct ReaderHost: UIViewRepresentable {
    let readers: [PageReader]
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.accessibilityElementsHidden = true
        for reader in readers {
            reader.webView.frame = container.bounds
            reader.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            reader.webView.accessibilityElementsHidden = true
            container.addSubview(reader.webView)
        }
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        for reader in readers where reader.webView.frame != view.bounds { reader.webView.frame = view.bounds }
    }
}
