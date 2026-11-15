import SwiftUI

struct Artwork: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "film").font(.title).foregroundStyle(.tertiary) }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct PosterCard: View {
    let title: Title
    var width: CGFloat = 144
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationLink(value: title) {
            VStack(alignment: .leading, spacing: 8) {
                Artwork(url: title.imageURL)
                    .frame(width: width, height: width * 1.48)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        if library.contains(title) {
                            Image(systemName: "bookmark.fill").font(.caption.weight(.semibold))
                                .padding(8).glassEffect(in: .circle).padding(8)
                        }
                    }
                Text(title.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Text(title.year)
                    if !title.rating.isEmpty { Label(title.rating, systemImage: "star.fill") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { library.play(title) }
            Button(library.contains(title) ? "Remove from Library" : "Save to Library",
                   systemImage: library.contains(title) ? "bookmark.slash" : "bookmark") { library.toggle(title) }
            ShareLink(item: title.siteURL)
        }
        .sensoryFeedback(.selection, trigger: library.contains(title))
        .accessibilityLabel("\(title.name), \(title.year), \(title.isSeries ? "TV show" : "movie")")
        .accessibilityIdentifier("title-\(title.id)")
    }
}

struct ShelfView: View {
    let shelf: Shelf
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(shelf.name).font(.title2.bold()).padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.titles) { PosterCard(title: $0) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

struct TitleGrid: View {
    let titles: [Title]
    var body: some View {
        GeometryReader { geometry in
            let columns = max(2, Int(geometry.size.width / 160))
            let width = (geometry.size.width - CGFloat(columns - 1) * 14) / CGFloat(columns)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
                          alignment: .leading, spacing: 24) {
                    ForEach(titles) { PosterCard(title: $0, width: width) }
                }.padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct FeaturedTitle: View {
    let title: Title
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: title.heroURL).frame(height: 440)
            LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text(title.name).font(.largeTitle.bold()).lineLimit(2)
                Text([title.year, title.isSeries ? "Series" : "Movie", title.rating.isEmpty ? nil : "★ \(title.rating)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Play", systemImage: "play.fill") { library.play(title) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                        NavigationLink(value: title) { Label("Details", systemImage: "info.circle") }
                            .buttonStyle(.glass).controlSize(.large)
                    }
                }
            }
            .foregroundStyle(.white).padding(24)
        }
        .frame(height: 440)
        .clipShape(.rect(cornerRadius: 30))
        .padding(.horizontal, 16)
    }
}

struct InlineNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "wifi.exclamationmark")
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }
}
