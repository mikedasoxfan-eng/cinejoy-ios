import SwiftUI
import UIKit
import AVKit

/// The app's explicit fullscreen route. An app-owned view controller *embeds* the
/// system AVPlayerViewController as a child (AVKit keeps its playback controls,
/// scrubbing, PiP and captions overlay) and owns dismissal through one visible
/// Liquid Glass return control. Because the app, not AVKit, closes this screen, the
/// real play/pause state can be read before anything is dismissed: there is no
/// automatic modal-close pause to interpret.
@MainActor final class NativeFullScreenContainer: UIViewController {
    let playerController: AVPlayerViewController
    private let session: NativePlaybackSession
    /// Called when the return control is pressed. The owner samples state and dismisses.
    private let requestClose: (NativeFullScreenContainer) -> Void
    /// Called if the container leaves the screen without the owner closing it.
    var dismissedWithoutOwner: ((NativeFullScreenContainer) -> Void)?
    private(set) var closedByOwner = false
    private var controlHost: UIHostingController<FullScreenReturnControl>?

    /// Room reserved above AVKit's own controls for the return control.
    private static let controlBand: CGFloat = 60

    init(playerController: AVPlayerViewController, session: NativePlaybackSession, requestClose: @escaping (NativeFullScreenContainer) -> Void) {
        self.playerController = playerController
        self.session = session
        self.requestClose = requestClose
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "native-fullscreen-player"

        addChild(playerController)
        playerController.view.frame = view.bounds
        playerController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerController.view)
        playerController.didMove(toParent: self)
        // AVKit lays its controls out inside its safe area; reserve the top band for
        // the return control so neither ever covers the other.
        playerController.additionalSafeAreaInsets = UIEdgeInsets(top: Self.controlBand, left: 0, bottom: 0, right: 0)

        let host = UIHostingController(rootView: FullScreenReturnControl(session: session) { [weak self] in
            guard let self else { return }
            self.requestClose(self)
        })
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])
        controlHost = host
    }

    /// Marks that the owner is closing, so disappearance is not treated as external.
    func beginOwnerClose() { closedByOwner = true }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil, !closedByOwner {
            dismissedWithoutOwner?(self)
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
}

/// The visible, always-available way back from the app's fullscreen.
struct FullScreenReturnControl: View {
    let session: NativePlaybackSession
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
          Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left", action: action)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Color("AccentColor"))
            .accessibilityIdentifier("native-fullscreen-return")
            .accessibilityHint("Returns to the player with the video in the same state")
          if !session.captionTracks.isEmpty {
            NativeCaptionMenu(tracks: session.captionTracks, selection: Binding(get: { session.selectedCaptionID }, set: {
                session.selectedCaptionID = $0
                session.fullScreenPresenter?.setCaptions(active: $0 != nil)
            }))
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityIdentifier("fullscreen-subtitles")
          }
        }
        .environment(\.colorScheme, .dark)
    }
}
