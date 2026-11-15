import SwiftUI

struct HomeScreen: View {
    @Environment(CatalogStore.self) private var catalog
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if let featured = catalog.titles.first { FeaturedTitle(title: featured) }
                if let error = catalog.error {
                    InlineNotice(text: error) { Task { await catalog.refresh(force: true) } }
                }
                ContinueWatchingRow()
                ForEach(catalog.shelves) { ShelfView(shelf: $0) }
                if catalog.shelves.isEmpty {
                    ContentUnavailableView {
                        Label("Loading Cinejoy", systemImage: "film.stack")
                    } description: {
                        Text("Getting tonight’s picks from Cinejoy.")
                    } actions: {
                        ProgressView()
                    }
                    .frame(minHeight: 320)
                }
            }
            .padding(.top, 4).padding(.bottom, 32)
        }
        .navigationTitle("Cinejoy")
        .refreshable { await catalog.refresh(force: true) }
    }
}

/// Reads watch history on its own, so playback progress updates never redraw
/// the whole Home screen.
struct ContinueWatchingRow: View {
    @Environment(LibraryStore.self) private var library
    private var continuing: [WatchEntry] { Array(library.history.filter { $0.fraction < 0.95 }.prefix(10)) }

    var body: some View {
        let entries = continuing
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue watching").font(.title3.bold()).padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(entries) { entry in
                            Button { library.play(entry.title, path: entry.path) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Artwork(url: entry.title.backdropURL(.wide), maxPixel: 700)
                                        .frame(width: 224, height: 126)
                                        .overlay(alignment: .bottom) {
                                            ProgressView(value: entry.fraction)
                                                .tint(Color("AccentColor"))
                                                .padding(.horizontal, 10).padding(.bottom, 8)
                                        }
                                        .overlay {
                                            Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                                                .padding(12).glassEffect(in: .circle)
                                                .environment(\.colorScheme, .dark)
                                        }
                                        .clipShape(.rect(cornerRadius: 14))
                                    Text(entry.title.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(entry.remaining).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 224, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove from Continue Watching", systemImage: "minus.circle", role: .destructive) { library.removeHistory(entry) }
                            }
                            .accessibilityLabel("Continue \(entry.title.name), \(entry.remaining)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct BrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var kind = "movie"
    var body: some View {
        let titles = catalog.titles.filter { $0.kind == kind }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Browse", selection: $kind) {
                    Text("Movies").tag("movie")
                    Text("TV Shows").tag("tv")
                }
                .pickerStyle(.segmented)
                if titles.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "film.stack",
                                           description: Text("Pull to refresh on Home to load the latest catalog."))
                } else {
                    TitleGridContent(titles: titles)
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }
        .navigationTitle("Browse")
        .sensoryFeedback(.selection, trigger: kind)
    }
}

struct SearchScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var query = ""
    @State private var searchIsPresented = false
    @State private var results: [Title] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var retry = 0

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var liveSearchEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CINEJOY_UI_TESTS"] != "1" || environment["CINEJOY_LIVE_SEARCH"] == "1"
    }

    var body: some View {
        Group {
            if term.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("Find your next favorite.").font(.title2.weight(.semibold)).padding(.horizontal, 20)
                        ForEach(catalog.shelves.prefix(2)) { ShelfView(shelf: $0) }
                    }
                    .padding(.top, 12).padding(.bottom, 24)
                }
            } else if results.isEmpty, isLoading {
                ProgressView("Searching Cinejoy…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty, let error {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { retry += 1 }.buttonStyle(.glass)
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: term)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isLoading {
                            Label { Text("Searching Cinejoy…") } icon: { ProgressView().controlSize(.small) }
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if error != nil {
                            Text("Showing titles saved on this device. Live search is unavailable.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        TitleGridContent(titles: results)
                    }
                    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, isPresented: $searchIsPresented, prompt: "Movies and TV shows")
        .onSubmit(of: .search) { searchIsPresented = false }
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(retry)#\(query)") { await search() }
    }

    /// Local matches show on the first keystroke; the live page read starts after a
    /// short pause in typing and is cancelled (with its hidden page) by the next keystroke.
    @MainActor private func search() async {
        let term = self.term
        guard !term.isEmpty else { results = []; error = nil; isLoading = false; return }
        let local = catalog.localMatches(term)
        results = local
        error = nil
        guard liveSearchEnabled else { isLoading = false; return }
        isLoading = true
        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        do {
            let live = try await catalog.search(term)
            guard !Task.isCancelled else { return }
            var ids = Set(live.map(\.id))
            results = live + local.filter { ids.insert($0.id).inserted }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Check your connection and try again."
        }
        isLoading = false
    }
}

struct LibraryScreen: View {
    @Environment(LibraryStore.self) private var library
    @State private var section = 0
    var body: some View {
        VStack(spacing: 12) {
            Picker("Library", selection: $section) { Text("Saved").tag(0); Text("History").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal, 20)
            if section == 0 {
                if library.saved.isEmpty {
                    ContentUnavailableView {
                        Label("A little movie-night planning", systemImage: "bookmark")
                    } description: {
                        Text("Save a movie or show and it will be waiting here.")
                    } actions: {
                        Button("Browse titles") { library.selectedTab = 1 }.buttonStyle(.glass)
                    }
                    .frame(maxHeight: .infinity)
                } else { TitleGrid(titles: library.saved) }
            } else {
                if library.history.isEmpty {
                    ContentUnavailableView("Pick up where you left off", systemImage: "clock", description: Text("Your watch history stays on this device."))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.history) { entry in
                            Button { library.play(entry.title, path: entry.path) } label: {
                                HStack(spacing: 14) {
                                    Artwork(url: entry.title.posterURL(.thumbnail), maxPixel: 240)
                                        .frame(width: 52, height: 78).clipShape(.rect(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.title.name).font(.headline).lineLimit(2)
                                        Text(entry.remaining).font(.subheadline).foregroundStyle(.secondary)
                                        ProgressView(value: entry.fraction).tint(Color("AccentColor"))
                                    }
                                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .padding(.vertical, 4)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .swipeActions { Button("Remove", role: .destructive) { library.removeHistory(entry) } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Your Library")
        .sensoryFeedback(.selection, trigger: section)
    }
}

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }.accessibilityIdentifier("appearance-picker")
                }
                Section {
                    Label("Saved on this device", systemImage: "iphone")
                    Text("Your library and watch history stay here. There is no account to create.").foregroundStyle(.secondary)
                    Button("Clear watch history", role: .destructive) { confirmClear = true }
                        .disabled(library.history.isEmpty)
                        .accessibilityIdentifier("clear-history")
                } header: { Text("Your Library") }
                Section("Catalog") {
                    if let updated = catalog.lastUpdated {
                        LabeledContent("Last updated") { Text(updated, format: .relative(presentation: .named)) }
                    } else {
                        LabeledContent("Last updated", value: "Bundled snapshot")
                    }
                    Button(catalog.isRefreshing ? "Refreshing…" : "Refresh now") { Task { await catalog.refresh(force: true) } }
                        .disabled(catalog.isRefreshing)
                }
                Section("About") {
                    LabeledContent("Cinejoy", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"))")
                    Link("Visit Cinejoy", destination: URL(string: "https://cinejoy.pk")!)
                    Text("An independent, personal-use client. Streaming is provided by Cinejoy and its providers.").font(.footnote).foregroundStyle(.secondary)
                    Text("Catalog artwork and metadata: TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .confirmationDialog("Clear watch history on this device?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { library.clearHistory() }
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .tint(Color("AccentColor"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
