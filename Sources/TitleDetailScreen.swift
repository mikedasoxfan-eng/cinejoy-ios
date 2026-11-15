import SwiftUI

struct TitleDetailScreen: View {
    let title: Title
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var info: SupplementalInfo?
    @State private var episodes: [Episode] = []
    @State private var seasons: [Int] = [1]
    @State private var season = 1
    @State private var isLoadingEpisodes = false
    @State private var episodeError: String?
    @State private var episodeDiagnostic = ""
    @State private var loadToken = UUID()
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                VStack(alignment: .leading, spacing: 20) {
                    actions
                    overview
                    if title.isSeries { episodeSection }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: title.siteURL).accessibilityIdentifier("share-title") }
        }
        .task {
            if let cached = catalog.cachedInfo(for: title) {
                info = cached
            } else {
                let loaded = await catalog.info(for: title)
                withAnimation(.easeOut(duration: 0.2)) { info = loaded }
            }
            // The season selector comes from public metadata as soon as it is known,
            // instead of waiting for the hidden episode page to finish rendering.
            if title.isSeries, let info, !info.publicSeasons.isEmpty { seasons = mergedSeasons(info.publicSeasons) }
        }
        .task(id: season) { if title.isSeries { await loadEpisodes() } }
        .sensoryFeedback(.selection, trigger: library.contains(title))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : -72) {
            backdrop
            if dynamicTypeSize.isAccessibilitySize {
                titleBlock.padding(.horizontal, 20)
            } else {
                HStack(alignment: .bottom, spacing: 16) {
                    PosterArtwork(title: title, cornerRadius: 12)
                        .frame(width: 104)
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
                        .accessibilityHidden(true)
                    titleBlock
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// Real wide art when the catalog has it; otherwise the poster, softened into an
    /// ambient field rather than cropped into a fake backdrop.
    private var backdrop: some View {
        let wide = title.hasWideArtwork
        return Color.clear
            .aspectRatio(wide ? CGFloat(4.0 / 3.0) : CGFloat(1.5), contentMode: .fit)
            .overlay {
                Artwork(url: wide ? title.backdropURL(.hero) : title.posterURL(.wide), maxPixel: wide ? 1400 : 500)
                    .blur(radius: wide ? 0 : 28, opaque: true)
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.4),
                                       .init(color: Color(.systemBackground).opacity(0.75), location: 0.78),
                                       .init(color: Color(.systemBackground), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.name).font(.title.bold())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(metadata).font(.subheadline).foregroundStyle(.secondary)
            if let rating = info?.imdb_rating, !rating.isEmpty {
                Label("\(rating) IMDb", systemImage: "star.fill")
                    .font(.subheadline.weight(.medium))
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metadata: String {
        var parts = [title.year, title.isSeries ? "TV Show" : "Movie"]
        if let runtime = info?.runtime, runtime > 0 { parts.append(runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m") }
        if let rating = info?.content_rating { parts.append(rating) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Actions

    private var resumeEntry: WatchEntry? {
        guard let entry = library.entry(for: title), entry.fraction < 0.95, entry.seconds >= 30 else { return nil }
        return entry
    }

    private var playLabel: String {
        if let entry = resumeEntry {
            if let episode = entry.episode { return "Resume \(episode.label)" }
            return "Resume"
        }
        return "Play"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassEffectContainer(spacing: 12) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button(playLabel, systemImage: "play.fill") { library.play(title) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .lineLimit(1)
                        .accessibilityIdentifier("play-title")
                    Button(library.contains(title) ? "Saved" : "Save", systemImage: library.contains(title) ? "bookmark.fill" : "bookmark") { library.toggle(title) }
                        .buttonStyle(.glass).controlSize(.large)
                        .lineLimit(1)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            if let entry = resumeEntry {
                HStack(spacing: 10) {
                    ProgressView(value: entry.fraction).tint(Color("AccentColor")).frame(maxWidth: 160)
                    Text(entry.remaining).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var overview: some View {
        let text = info?.description ?? title.overview
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.body).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 4)
                    .textSelection(.enabled)
                if text.count > 220 {
                    Button(expanded ? "Less" : "More") { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    // MARK: Episodes

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episodes").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if seasons.count > 1 {
                    Menu {
                        Picker("Season", selection: $season) {
                            ForEach(seasons, id: \.self) { Text("Season \($0)").tag($0) }
                        }
                    } label: { Label("Season \(season)", systemImage: "chevron.down") }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("season-picker")
                        .accessibilityValue(ProcessInfo.processInfo.environment["CINEJOY_UI_TESTS"] == "1" ? episodeDiagnostic : "")
                } else { Text("Season \(season)").foregroundStyle(.secondary) }
            }
            if isLoadingEpisodes && episodes.isEmpty {
                ForEach(0..<3, id: \.self) { _ in EpisodeRowPlaceholder() }
            }
            if let episodeError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(episodeError).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await loadEpisodes(force: true) } }.buttonStyle(.glass)
                }
            }
            ForEach(episodes) { episode in
                Button { library.play(title, path: episode.path) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Artwork(url: .artwork(episode.image, size: .still), maxPixel: 420)
                            .frame(width: 132, height: 74)
                            .overlay(alignment: .bottom) { episodeProgress(episode) }
                            .overlay {
                                Image(systemName: "play.fill").font(.footnote).foregroundStyle(.white)
                                    .padding(9).glassEffect(in: .circle).environment(\.colorScheme, .dark)
                            }
                            .clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(episode.number). \(episode.name)").font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(episode.overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Play episode \(episode.number), \(episode.name)")
                    .accessibilityIdentifier("episode-\(episode.path)")
            }
        }
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.2), value: episodes)
    }

    @ViewBuilder private func episodeProgress(_ episode: Episode) -> some View {
        if let entry = library.entry(for: title), entry.path == episode.path, entry.fraction > 0.01 {
            ProgressView(value: entry.fraction).tint(Color("AccentColor"))
                .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }

    /// Cached episodes appear immediately; a live read refreshes them when stale.
    @MainActor private func loadEpisodes(force: Bool = false) async {
        let token = UUID()
        loadToken = token
        isLoadingEpisodes = false
        episodeError = nil
        episodeDiagnostic = ""
        let cached = catalog.cachedEpisodes(for: title, season: season)
        if let cached { apply(cached.page) } else { episodes = [] }
        if !force, let cached, !cached.page.episodes.isEmpty, cached.isFresh(30 * 60) { return }
        isLoadingEpisodes = true
        defer { if loadToken == token { isLoadingEpisodes = false } }
        do {
            let page = try await catalog.loadEpisodes(for: title, season: season)
            try Task.checkCancellation()
            guard loadToken == token else { return }
            apply(page)
            if episodes.isEmpty { episodeError = "Episode information is unavailable. Play starts with the first episode." }
        } catch is CancellationError {} catch {
            guard loadToken == token else { return }
            if episodes.isEmpty { episodeError = "Couldn’t load episodes. Check your connection and try again." }
            episodeDiagnostic = (error as NSError).localizedDescription
        }
    }

    private func apply(_ page: CatalogPage) {
        if !page.episodes.isEmpty { episodes = page.episodes }
        if !page.seasons.isEmpty { seasons = mergedSeasons(page.seasons) }
    }

    /// Union of seasons already offered, seasons the page shows (including specials
    /// as season 0) and the public season count. Never shrinks while the screen is
    /// open, so a slow or partial page cannot take away a season the user can pick.
    private func mergedSeasons(_ incoming: [Int]) -> [Int] {
        let all = Set(seasons + incoming + (info?.publicSeasons ?? []) + [season])
        return all.filter { (0...100).contains($0) }.sorted()
    }
}
