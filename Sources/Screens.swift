import SwiftUI

struct HomeScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let featured = catalog.titles.first { FeaturedTitle(title: featured) }
                if let error = catalog.error { InlineNotice(text: error) }
                if !library.history.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Continue watching").font(.title2.bold()).padding(.horizontal, 20)
                        ScrollView(.horizontal) {
                            HStack(spacing: 14) {
                                ForEach(library.history.filter { $0.fraction < 0.95 }.prefix(10)) { entry in
                                    Button { library.play(entry.title, path: entry.path) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Artwork(url: entry.title.heroURL).frame(width: 240, height: 135)
                                                .clipShape(.rect(cornerRadius: 16))
                                            ProgressView(value: entry.fraction).tint(.accentColor)
                                            Text(entry.title.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(entry.remaining).font(.caption).foregroundStyle(.secondary)
                                        }.frame(width: 240)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.contentMargins(.horizontal, 20).scrollIndicators(.hidden)
                    }
                }
                ForEach(catalog.shelves) { ShelfView(shelf: $0) }
                if catalog.shelves.isEmpty {
                    ContentUnavailableView("Loading Cinejoy", systemImage: "film.stack", description: Text("Your next movie night is on its way."))
                        .overlay(alignment: .bottom) { ProgressView() }
                }
            }.padding(.top, 8).padding(.bottom, 32)
        }
        .navigationTitle("Cinejoy")
        .refreshable { await catalog.refresh(force: true) }
    }
}

struct BrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var kind = "movie"
    var body: some View {
        VStack(spacing: 20) {
            Picker("Browse", selection: $kind) {
                Text("Movies").tag("movie")
                Text("TV Shows").tag("tv")
            }.pickerStyle(.segmented).padding(.horizontal, 20)
            TitleGrid(titles: catalog.titles.filter { $0.kind == kind })
        }
        .navigationTitle("Browse")
        .sensoryFeedback(.selection, trigger: kind)
    }
}

struct SearchScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var query = ""
    @State private var results: [Title] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var reader = PageReader()

    var body: some View {
        VStack(spacing: 16) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("Find your next favorite.").font(.title2.weight(.semibold)).padding(.horizontal, 20)
                        ForEach(catalog.shelves.prefix(2)) { ShelfView(shelf: $0) }
                    }.padding(.top, 16)
                }
            } else if isLoading && results.isEmpty {
                Spacer(); ProgressView("Searching Cinejoy…"); Spacer()
            } else if let error, results.isEmpty {
                ContentUnavailableView("Search unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Try again") { Task { await search() } }.buttonStyle(.glass)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                if isLoading { ProgressView().controlSize(.small) }
                TitleGrid(titles: results)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies and TV shows")
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(450)); try Task.checkCancellation(); await search() }
            catch {}
        }
        .background { ReaderHost(reader: reader).frame(width: 430, height: 932).opacity(0.001).allowsHitTesting(false).accessibilityHidden(true) }
    }

    @MainActor private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { reader.cancel(); results = []; error = nil; isLoading = false; return }
        isLoading = true
        error = nil
        results = catalog.titles.filter { $0.name.localizedCaseInsensitiveContains(term) }
        defer { if query.trimmingCharacters(in: .whitespacesAndNewlines) == term { isLoading = false } }
        var components = URLComponents()
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: term)]
        do {
            let page = try await reader.read(path: components.string!)
            try Task.checkCancellation()
            if term == query.trimmingCharacters(in: .whitespacesAndNewlines) { results = page.titles }
        } catch is CancellationError {} catch {
            if term == query.trimmingCharacters(in: .whitespacesAndNewlines) { self.error = "Check your connection and try again." }
        }
    }
}

struct LibraryScreen: View {
    @Environment(LibraryStore.self) private var library
    @State private var section = 0
    var body: some View {
        VStack(spacing: 20) {
            Picker("Library", selection: $section) { Text("Saved").tag(0); Text("History").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal, 20)
            if section == 0 {
                if library.saved.isEmpty {
                    ContentUnavailableView("A little movie-night planning", systemImage: "bookmark", description: Text("Save a movie or show and it will be waiting here."))
                } else { TitleGrid(titles: library.saved) }
            } else {
                if library.history.isEmpty {
                    ContentUnavailableView("Pick up where you left off", systemImage: "clock", description: Text("Your watch history stays on this device."))
                } else {
                    List {
                        ForEach(library.history) { entry in
                            Button { library.play(entry.title, path: entry.path) } label: {
                                HStack(spacing: 14) {
                                    Artwork(url: entry.title.imageURL).frame(width: 52, height: 76).clipShape(.rect(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.title.name).font(.headline)
                                        Text(entry.remaining).font(.subheadline).foregroundStyle(.secondary)
                                        ProgressView(value: entry.fraction)
                                    }
                                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                                .swipeActions { Button("Remove", role: .destructive) { library.removeHistory(entry) } }
                        }
                    }.listStyle(.plain)
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
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                }
                Section {
                    Label("Saved on this device", systemImage: "iphone")
                    Text("Your library and watch history stay here. There is no account to create.").foregroundStyle(.secondary)
                    Button("Clear watch history", role: .destructive) { confirmClear = true }
                        .disabled(library.history.isEmpty)
                } header: { Text("Your Library") }
                Section("About") {
                    LabeledContent("Cinejoy", value: "1.0")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
