import SwiftUI

struct TitleDetailScreen: View {
    let title: Title
    @Environment(LibraryStore.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var info: SupplementalInfo?
    @State private var episodes: [Episode] = []
    @State private var seasons: [Int] = [1]
    @State private var season = 1
    @State private var isLoadingEpisodes = false
    @State private var episodeError: String?
    @State private var reader = PageReader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GeometryReader { geometry in
                    Artwork(url: title.heroURL)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(.rect(cornerRadius: 24))
                }
                    .frame(height: 310)
                    .padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 18) {
                    Text(title.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(metadata).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    GlassEffectContainer(spacing: 12) {
                        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            Button("Play", systemImage: "play.fill") { library.play(title) }
                                .buttonStyle(.glassProminent).controlSize(.large)
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                .lineLimit(1)
                            Button(library.contains(title) ? "Saved" : "Save", systemImage: library.contains(title) ? "bookmark.fill" : "bookmark") { library.toggle(title) }
                                .buttonStyle(.glass).controlSize(.large)
                                .lineLimit(1)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    if !(info?.description ?? title.overview).isEmpty {
                        Text(info?.description ?? title.overview).font(.body).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let rating = info?.imdb_rating, !rating.isEmpty {
                        Label("\(rating) on IMDb", systemImage: "star.fill").font(.subheadline.weight(.medium))
                    }
                    if title.isSeries { episodeSection }
                }.padding(.horizontal, 20)
            }.padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: title.siteURL) }
        }
        .task { info = try? await TitleInfoService.info(for: title) }
        .task(id: season) { if title.isSeries { await loadEpisodes() } }
        .sensoryFeedback(.selection, trigger: library.contains(title))
        .background { ReaderHost(reader: reader).frame(width: 430, height: 932).opacity(0.001).allowsHitTesting(false).accessibilityHidden(true) }
    }

    private var metadata: String {
        var parts = [title.year, title.isSeries ? "TV Show" : "Movie"]
        if let runtime = info?.runtime, runtime > 0 { parts.append("\(runtime / 60)h \(runtime % 60)m") }
        if let rating = info?.content_rating { parts.append(rating) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episodes").font(.title2.bold())
                Spacer()
                if seasons.count > 1 {
                    Menu {
                        Picker("Season", selection: $season) {
                            ForEach(seasons, id: \.self) { Text("Season \($0)").tag($0) }
                        }
                    } label: { Label("Season \(season)", systemImage: "chevron.down") }
                        .buttonStyle(.glass)
                } else { Text("Season \(season)").foregroundStyle(.secondary) }
            }
            if isLoadingEpisodes { ProgressView("Loading episodes…").padding(.vertical) }
            if let episodeError {
                Text(episodeError).font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await loadEpisodes() } }.buttonStyle(.glass)
            }
            ForEach(episodes) { episode in
                Button { library.play(title, path: episode.path) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Artwork(url: URL(string: episode.image)).frame(width: 120, height: 78).clipShape(.rect(cornerRadius: 12))
                            .overlay { Image(systemName: "play.fill").foregroundStyle(.white).padding(10).glassEffect(in: .circle).environment(\.colorScheme, .dark) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(episode.number). \(episode.name)").font(.subheadline.weight(.semibold))
                            Text(episode.overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Play episode \(episode.number), \(episode.name)")
            }
        }.padding(.top, 8)
    }

    @MainActor private func loadEpisodes() async {
        isLoadingEpisodes = true
        episodeError = nil
        episodes = []
        defer { isLoadingEpisodes = false }
        do {
            let page = try await reader.read(path: title.path, season: season)
            try Task.checkCancellation()
            episodes = page.episodes
            if !page.seasons.isEmpty { seasons = page.seasons }
            if episodes.isEmpty { episodeError = "Episode information is unavailable. Play starts with the first episode." }
        } catch is CancellationError {} catch {
            episodeError = "Couldn’t load episodes. Check your connection and try again."
        }
    }
}
