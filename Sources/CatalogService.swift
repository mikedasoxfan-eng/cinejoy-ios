import Foundation
import Observation
import WebKit
import SwiftUI

// Reads the same public pages the user can browse. No copied TMDB credential,
// account token, protected resolver implementation, or private endpoint is needed.
@MainActor final class PageReader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var generation = UUID()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.addEventListener('DOMContentLoaded',()=>{const s=document.createElement('style');s.textContent='[role=dialog]{display:none!important}';document.head.append(s)});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 430, height: 932), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func read(path: String, season: Int? = nil) async throws -> CatalogPage {
        let requestID = UUID()
        generation = requestID
        defer {
            if requestID == generation {
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
            }
        }
        guard let url = URL(string: "https://cinejoy.pk\(path)") else { throw URLError(.badURL) }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
        var last: CatalogPage?
        for attempt in 0..<50 {
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            guard requestID == generation else { throw CancellationError() }
            guard let current = webView.url, current.path == url.path, current.query == url.query, attempt >= 3 else { continue }
            if path.hasPrefix("/search"), url.query != nil {
                let stillShowingSuggestions = (try? await webView.evaluateJavaScript("[...document.querySelectorAll('h2')].some(h=>h.textContent.trim()==='Trending Today')")) as? Bool
                if stillShowingSuggestions == true { continue }
            }
            if let season, attempt > 4 {
                if let scriptURL = Bundle.main.url(forResource: "SeasonSelection", withExtension: "js"),
                   let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
                    _ = try? await webView.evaluateJavaScript(source.replacingOccurrences(of: "__SEASON__", with: String(season)))
                }
            }
            guard let scriptURL = Bundle.main.url(forResource: "CatalogExtraction", withExtension: "js"),
                  let script = try? String(contentsOf: scriptURL, encoding: .utf8),
                  let text = try? await webView.evaluateJavaScript(script) as? String,
                  let data = text.data(using: .utf8),
                  let page = try? JSONDecoder().decode(CatalogPage.self, from: data) else { continue }
            if let season, !page.episodes.contains(where: { $0.path.split(separator: "/").dropLast().last == Substring(String(season)) }) { continue }
            if !page.titles.isEmpty || !page.episodes.isEmpty {
                if let previous = last, previous.titles.count == page.titles.count,
                   previous.episodes.count == page.episodes.count { return page }
                last = page
            }
            if attempt > 12, path.hasPrefix("/search"), !webView.isLoading, last == nil {
                let empty = (try? await webView.evaluateJavaScript("document.body.innerText.includes('No results') || document.body.innerText.includes('No titles')")) as? Bool
                if empty == true { return CatalogPage() }
            }
        }
        if let last { return last }
        throw URLError(.timedOut)
    }

    func cancel() { generation = UUID(); webView.stopLoading(); webView.loadHTMLString("", baseURL: nil) }
}

@MainActor @Observable final class CatalogStore {
    var shelves: [Shelf] = []
    var isRefreshing = false
    var error: String?
    let reader = PageReader()
    private var didLoad = false

    init() {
        let cache = URL.cachesDirectory.appending(path: "cinejoy-catalog.json")
        let sources = [cache, Bundle.main.url(forResource: "CatalogSeed", withExtension: "json")].compactMap { $0 }
        for source in sources {
            if let data = try? Data(contentsOf: source), let page = try? JSONDecoder().decode(CatalogPage.self, from: data), !page.shelves.isEmpty {
                shelves = page.shelves
                break
            }
        }
    }

    var titles: [Title] {
        var ids = Set<String>()
        return shelves.flatMap(\.titles).filter { ids.insert($0.id).inserted }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing, force || !didLoad else { return }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false }
        do {
            let page = try await reader.read(path: "/")
            if !page.shelves.isEmpty { shelves = page.shelves }
            else if !page.titles.isEmpty { shelves = [Shelf(name: "Discover", titles: page.titles)] }
            if let data = try? JSONEncoder().encode(page) {
                try? data.write(to: URL.cachesDirectory.appending(path: "cinejoy-catalog.json"), options: .atomic)
            }
            didLoad = true
        } catch is CancellationError {} catch {
            self.error = "Live catalog unavailable. Your last catalog is still here. Pull to try again."
        }
    }
}

enum TitleInfoService {
    static func info(for title: Title) async throws -> SupplementalInfo {
        var components = URLComponents(string: "https://api2.wing.st/info")!
        components.queryItems = [URLQueryItem(name: "type", value: title.kind), URLQueryItem(name: "tmdb", value: String(title.tmdbID))]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SupplementalInfo.self, from: data)
    }
}

// WebKit needs a view in the hierarchy for reliable page lifecycle/rendering.
// This inert, inaccessible backing view supplies catalog data to native screens.
struct ReaderHost: UIViewRepresentable {
    let reader: PageReader
    func makeUIView(context: Context) -> WKWebView { reader.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
