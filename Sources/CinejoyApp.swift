import SwiftUI

@main struct CinejoyApp: App {
    @State private var library = LibraryStore()
    @State private var catalog = CatalogStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(catalog)
                .tint(Color("AccentColor"))
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var library = library
        TabView(selection: $library.selectedTab) {
            Tab("Home", systemImage: "house", value: 0) {
                CineNavigation { HomeScreen() }
            }
            Tab("Browse", systemImage: "square.grid.2x2", value: 1) {
                CineNavigation { BrowseScreen() }
            }
            Tab("Library", systemImage: "rectangle.stack", value: 2) {
                CineNavigation { LibraryScreen() }
            }
            Tab(value: 3, role: .search) {
                CineNavigation { SearchScreen() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(ResumeBarModifier())
        .sheet(isPresented: $library.showSettings) { SettingsScreen() }
        .fullScreenCover(item: $library.playback) { playback in
            PlayerScreen(playback: playback)
                .id(playback.id)
        }
        .background {
            // Hidden catalog readers (DOM only; images, media and fonts are blocked).
            ReaderHost(readers: catalog.readers)
                .frame(width: 430, height: 932)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task {
            if ProcessInfo.processInfo.environment["CINEJOY_UI_TESTS"] != "1" { await catalog.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { library.flush() }
        }
    }
}

/// Reads history itself so a progress checkpoint only re-evaluates the accessory,
/// not the tab hierarchy (and the player cover) beneath RootView.
struct ResumeBarModifier: ViewModifier {
    @Environment(LibraryStore.self) private var library

    @ViewBuilder func body(content: Content) -> some View {
        let entry = library.history.first(where: { $0.fraction < 0.95 })
        if #available(iOS 26.2, *) {
            content.tabViewBottomAccessory(isEnabled: entry != nil) {
                if let entry { ResumeAccessory(entry: entry) }
            }
        } else if let entry {
            content.tabViewBottomAccessory { ResumeAccessory(entry: entry) }
        } else { content }
    }
}

struct CineNavigation<Content: View>: View {
    @Environment(LibraryStore.self) private var library
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Title.self) { TitleDetailScreen(title: $0) }
                .navigationDestination(for: Shelf.self) { ShelfScreen(shelf: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "slider.horizontal.3") { library.showSettings = true }
                    }
                }
        }
    }
}

struct ResumeAccessory: View {
    let entry: WatchEntry
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button { library.play(entry.title, path: entry.path) } label: {
            HStack(spacing: 12) {
                Artwork(url: entry.title.posterURL(.thumbnail), maxPixel: 160)
                    .frame(width: 30, height: 44).clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(entry.remaining).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill").font(.title3).frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue \(entry.title.name), \(entry.remaining)")
    }
}
