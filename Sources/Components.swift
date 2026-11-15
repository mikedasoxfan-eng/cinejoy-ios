import SwiftUI
import UIKit

/// Cached, downsampled artwork. A memory hit draws in the first frame, so
/// recycled cells and returning screens never flash a placeholder.
struct Artwork: View {
    let url: URL?
    var maxPixel: Int
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, maxPixel: Int = 800) {
        self.url = url
        self.maxPixel = maxPixel
        _image = State(initialValue: ImagePipeline.cached(url, maxPixel: maxPixel))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "film").font(.title2).foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if let hit = ImagePipeline.cached(url, maxPixel: maxPixel) {
            if image !== hit { image = hit }
            return
        }
        // A reused view whose URL changed must not keep showing the previous art.
        if image != nil { image = nil }
        failed = false
        let loaded = await ImagePipeline.shared.image(url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        failed = loaded == nil
    }
}

/// A 2:3 poster that fills whatever width its container offers.
struct PosterArtwork: View {
    let title: Title
    var cornerRadius: CGFloat = 12
    var maxPixel: Int = 520
    var body: some View {
        Color.clear
            .aspectRatio(CGFloat(2.0 / 3.0), contentMode: .fit)
            .overlay { Artwork(url: title.posterURL(.poster), maxPixel: maxPixel) }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}

struct PosterCard: View {
    let title: Title
    /// A fixed width for horizontal shelves; nil fills the grid column.
    var width: CGFloat? = 124
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let saved = library.contains(title)
        NavigationLink(value: title) {
            VStack(alignment: .leading, spacing: 6) {
                PosterArtwork(title: title)
                    .overlay(alignment: .topTrailing) {
                        if saved {
                            Image(systemName: "bookmark.fill").font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(7).glassEffect(in: .circle).padding(6)
                                .environment(\.colorScheme, .dark)
                        }
                    }
                Text(title.name).font(.footnote.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { library.play(title) }
            Button(saved ? "Remove from Library" : "Save to Library",
                   systemImage: saved ? "bookmark.slash" : "bookmark") { library.toggle(title) }
            ShareLink(item: title.siteURL)
        } preview: {
            PosterArtwork(title: title, cornerRadius: 0, maxPixel: 520).frame(width: 240)
        }
        .sensoryFeedback(.selection, trigger: saved)
        .accessibilityLabel("\(title.name), \(title.year), \(title.isSeries ? "TV show" : "movie")")
        .accessibilityIdentifier("title-\(title.id)")
    }

    private var caption: String {
        var parts = [title.year]
        if !title.rating.isEmpty { parts.append("★ \(title.rating)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

struct ShelfView: View {
    let shelf: Shelf
    var limit = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: shelf) {
                HStack(spacing: 6) {
                    Text(shelf.name).font(.title3.bold()).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityLabel("\(shelf.name), see all \(shelf.titles.count)")
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.titles.prefix(limit)) { PosterCard(title: $0) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// A scrolling grid of posters: three columns on iPhone, more on wider screens.
struct TitleGrid: View {
    let titles: [Title]
    var body: some View {
        ScrollView {
            TitleGridContent(titles: titles)
                .padding(.horizontal, 20)
                .padding(.top, 4).padding(.bottom, 24)
        }
    }
}

struct TitleGridContent: View {
    let titles: [Title]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 104, maximum: 180), spacing: 12, alignment: .top)]
    }
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(titles) { PosterCard(title: $0, width: nil) }
        }
    }
}

/// A full shelf from Home, reached from its header.
struct ShelfScreen: View {
    let shelf: Shelf
    var body: some View {
        TitleGrid(titles: shelf.titles)
            .navigationTitle(shelf.name)
            .navigationBarTitleDisplayMode(.large)
    }
}

struct FeaturedTitle: View {
    let title: Title
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    Color.clear.aspectRatio(CGFloat(16.0 / 9.0), contentMode: .fit)
                        .overlay { Artwork(url: title.backdropURL(.hero), maxPixel: 1400) }
                        .clipped()
                    details.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.black)
                }
                .clipShape(.rect(cornerRadius: 28))
            } else {
                // About half the visible height: the hero leads without pushing
                // every shelf below the fold (it was a fixed 440 pt).
                Color.clear
                    .containerRelativeFrame(.vertical) { length, _ in min(420, max(300, length * 0.47)) }
                    .overlay { Artwork(url: title.hasWideArtwork ? title.backdropURL(.hero) : title.posterURL(.wide), maxPixel: 1400) }
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                               .init(color: .black.opacity(0.55), location: 0.62),
                                               .init(color: .black.opacity(0.94), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) { details.padding(20) }
                    .clipShape(.rect(cornerRadius: 28))
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.name).font(.largeTitle.bold()).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text([title.year, title.isSeries ? "Series" : "Movie", title.rating.isEmpty ? nil : "★ \(title.rating)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            if !title.overview.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                Text(title.overview).font(.footnote).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
            }
            GlassEffectContainer(spacing: 12) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button("Play", systemImage: "play.fill") { library.play(title) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    NavigationLink(value: title) { Label("Details", systemImage: "info.circle") }
                        .buttonStyle(.glass).controlSize(.large)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// An in-place notice for a block that could not refresh; existing content stays.
struct InlineNotice: View {
    let text: String
    var retry: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let retry {
                Button("Retry", action: retry).font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Loading rows at the real episode row size, so content never jumps when it arrives.
struct EpisodeRowPlaceholder: View {
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: compact ? 12 : 14) {
            RoundedRectangle(cornerRadius: compact ? 10 : 12).fill(.quaternary)
                .frame(width: compact ? 112 : 132, height: compact ? 63 : 74)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.7)).frame(height: 10)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.7)).frame(width: 120, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}
