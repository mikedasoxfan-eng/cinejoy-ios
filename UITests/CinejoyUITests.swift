import XCTest

final class CinejoyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Synthetic local movie verifies the real AVKit overlay and its clock without
    /// letting a provider outage masquerade as a renderer failure.
    @MainActor func testNativeCaptionRenderer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launchEnvironment["CINEJOY_CAPTION_QA"] = "1"
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["caption-qa-status"].waitForExistence(timeout: 15))
        let playing = NSPredicate(format: "label == %@", "Playing")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: app.staticTexts["caption-qa-status"])], timeout: 15), .completed)
        app.buttons["First cue"].tap()
        app.buttons["Subtitles"].tap()
        app.buttons["English QA"].tap()
        let caption = app.staticTexts["native-caption-text"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, "First caption & timing", "HTML styling is stripped and entities decoded")
        capture("captions-01-inline-first", app)
        app.buttons["Pause and seek"].tap()
        let second = NSPredicate(format: "label CONTAINS %@", "Second caption")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: second, object: caption)], timeout: 5), .completed,
                       "Seeking while paused refreshes the displayed cue")
        capture("captions-02-paused-seek", app)
        app.buttons["Full Screen"].tap()
        XCTAssertTrue(app.buttons["native-fullscreen-return"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "native-caption-text", "Second caption")).firstMatch.waitForExistence(timeout: 5))
        capture("captions-03-fullscreen-portrait", app)
        app.buttons["fullscreen-subtitles"].tap(); app.buttons["Off"].tap()
        XCTAssertTrue(caption.waitForNonExistence(timeout: 5), "Captions can be disabled inside fullscreen")
        app.buttons["fullscreen-subtitles"].tap(); app.buttons["English QA"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "Captions can be enabled inside fullscreen")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        capture("captions-04-fullscreen-landscape", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "native-caption-text", "Second caption")).firstMatch.exists)
        app.buttons["native-fullscreen-return"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Subtitles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["caption-qa-status"].label, "Paused", "Returning preserves the paused state")
        XCTAssertEqual(Double(app.staticTexts["caption-qa-clock"].label) ?? -1, 15, accuracy: 0.3, "Returning preserves the caption clock")
        app.buttons["Subtitles"].tap(); app.buttons["Off"].tap()
        XCTAssertTrue(caption.waitForNonExistence(timeout: 5), "Off removes the native caption overlay")
        capture("captions-05-off", app)
        app.buttons["Subtitles"].tap(); app.buttons["English QA"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        let before = Double(app.staticTexts["caption-qa-clock"].label) ?? -1
        app.buttons["Resume"].tap()
        let advancing = NSPredicate { _, _ in (Double(app.staticTexts["caption-qa-clock"].label) ?? -1) > before + 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: nil)], timeout: 5), .completed)
        capture("captions-06-resumed", app)
    }

    /// Separately exercises the actual public provider's subtitle selection and
    /// transfer into the native menu. Does not claim network video playback.
    @MainActor func testLiveSubtitleBridge() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Inception")
        let title = app.buttons["title-movie:27205"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap()
        let play = app.buttons["play-title"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        let close = app.buttons["Close player"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        app.buttons["Playback options"].tap(); app.buttons["Find subtitles"].tap()
        let web = app.webViews.firstMatch
        let english = web.buttons.matching(NSPredicate(format: "label MATCHES %@", "en English\\s+[0-9]+" )).firstMatch
        if !english.waitForExistence(timeout: 20) {
            let subtitles = web.buttons["Subtitles"]
            XCTAssertTrue(subtitles.waitForExistence(timeout: 20)); subtitles.tap()
        }
        XCTAssertTrue(english.waitForExistence(timeout: 15)); english.tap()
        let track = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "[hdpopcorns]-Inception-1080p-English-Subtitles-Free-Download-19.srt")).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 10)); track.tap()
        let loaded = NSPredicate(format: "value MATCHES %@", ".*captionCues=[1-9][0-9]*.*")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: close)], timeout: 30), .completed,
                       "The actual provider's loaded cues reach the native session")
        capture("captions-07-live-provider", app)
        app.buttons["Back to video"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Playback options"].waitForExistence(timeout: 5))
        XCTAssertTrue((close.value as? String ?? "").contains("captionSelected=true"), "The provider's selected track is already selected natively")
        app.buttons["Playback options"].tap()
        // Scope to the open native menu; the info panel also has a Subtitles button.
        app.collectionViews.buttons["Subtitles"].firstMatch.tap()
        let nativeTrack = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "hdpopcorns")).firstMatch
        XCTAssertTrue(nativeTrack.waitForExistence(timeout: 5), "The live English track appears in the native subtitle menu")
        capture("captions-08-live-native-menu", app)
        nativeTrack.tap()
    }

    /// Every failed test keeps evidence, including failures that happen before a
    /// test's own capture() (for example a missing element after a long wait):
    /// the physical screen and the full accessibility hierarchy of the app.
    override func tearDown() async throws {
        let failed = (testRun?.failureCount ?? 0) + (testRun?.unexpectedExceptionCount ?? 0) > 0
        if failed { await MainActor.run { captureFailureEvidence() } }
        try await super.tearDown()
    }

    @MainActor private func captureFailureEvidence() {
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "failure-screen"
        screen.lifetime = .keepAlways
        add(screen)
        let app = XCUIApplication()
        let hierarchy = XCTAttachment(string: app.state == .notRunning ? "App not running" : app.debugDescription)
        hierarchy.name = "failure-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        if app.state != .notRunning, app.buttons["Close player"].exists {
            let media = XCTAttachment(string: app.buttons["Close player"].value as? String ?? "No media diagnostics")
            media.name = "failure-media-state"
            media.lifetime = .keepAlways
            add(media)
        }
    }

    /// The light Home hero must render its text over the art, not just the Play
    /// button. Uses the app's real appearance preference, then checks that the
    /// title, metadata and Details action are on screen inside the hero card.
    @MainActor func testLightHomeHeroCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launchArguments = ["-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Cinejoy"].waitForExistence(timeout: 15))
        let hero = app.otherElements["featured-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "The featured hero is present")
        let title = app.staticTexts["featured-title"]
        let meta = app.staticTexts["featured-metadata"]
        let details = hero.buttons["Details"]
        for element in [title, meta, details] {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) exists in light mode")
            XCTAssertTrue(element.isHittable, "\(element) is on screen in light mode")
            XCTAssertTrue(hero.frame.contains(element.frame), "\(element) lies inside the hero card")
        }
        XCTAssertFalse((title.label).isEmpty, "The hero title has text")
        capture("home-light-hero", app)
    }

    @MainActor func testHomeScreenCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launchArguments = ["-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Cinejoy"].waitForExistence(timeout: 15))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let announcement = springboard.staticTexts["Ready for Apple Intelligence"]
        // New Simulator devices can present this system banner after launch.
        // Dismiss it through the system UI before judging the app's layout.
        for _ in 0..<3 {
            if !announcement.exists { break }
            announcement.swipeUp()
        }
        XCTAssertFalse(announcement.exists, "The app capture is free of the setup notification")
        capture("home-screen", app)
    }

    @MainActor func testNativeBrowsingAndLocalLibrary() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["Cinejoy"].waitForExistence(timeout: 15))
        capture("01-home", app)

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["A little movie-night planning"].waitForExistence(timeout: 5))
        capture("01b-library-empty", app)
        app.tabBars.buttons["Browse"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        capture("02-browse", app)
        app.segmentedControls.buttons["TV Shows"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'title-tv:'")).firstMatch.waitForExistence(timeout: 5))
        capture("02b-browse-tv", app)
        app.segmentedControls.buttons["Movies"].tap()
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'title-'")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 5))
        poster.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        capture("03-title-details", app)
        save.tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 5))
        let share = app.buttons["share-title"]
        XCTAssertTrue(share.waitForExistence(timeout: 5)); share.tap()
        // Capture the native activity sheet without choosing a destination. The
        // persistence check's full app relaunch also closes this presentation.
        capture("03b-share", app)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'title-'")).firstMatch.waitForExistence(timeout: 5), "Saved titles survive a full app relaunch")
        capture("04-local-library", app)

        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find your next favorite."].waitForExistence(timeout: 5))
        capture("05a-search-discovery", app)
        search.tap()
        search.typeText("Odyssey")
        XCTAssertTrue(app.buttons["title-movie:1368337"].waitForExistence(timeout: 8))
        capture("05-native-search", app)

        search.typeText("\n")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("06-settings", app)
        XCTAssertFalse(app.buttons["Log in"].exists)
        XCTAssertFalse(app.buttons["Sign up"].exists)
    }

    @MainActor func testSearchEmptyStateAndLiveResults() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launchEnvironment["CINEJOY_LIVE_SEARCH"] = "1"
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Arrival")
        XCTAssertTrue(app.buttons["title-movie:329865"].waitForExistence(timeout: 30), "A title absent from the bundled catalog must arrive from live search")
        capture("07-live-search", app)
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "zzzzcinejoynomatch999")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch.waitForExistence(timeout: 30))
        capture("08-search-empty", app)
    }

    @MainActor func testTVSeasonSelection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Breaking Bad")
        let title = app.buttons["title-tv:1396"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap()
        app.swipeUp()
        let seasonMenu = app.buttons["season-picker"]
        XCTAssertTrue(seasonMenu.waitForExistence(timeout: 30))
        capture("09-tv-episodes", app)
        seasonMenu.tap()
        let secondSeason = app.buttons["Season 2"]
        XCTAssertTrue(secondSeason.waitForExistence(timeout: 5))
        capture("09b-season-menu", app)
        secondSeason.tap()
        let episode = app.buttons["episode-/watch/tv/1396/2/1"]
        XCTAssertTrue(episode.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Loading episodes…"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(episode.label, "Play episode 1, Seven Thirty-Seven")
        let details = app.scrollViews.firstMatch
        for _ in 0..<6 {
            if episode.isHittable { break }
            // Loading changes the scroll content height. Move toward the actual
            // row instead of blindly swiping it above the visible viewport.
            let below = episode.frame.midY > details.frame.midY
            let start = details.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.7 : 0.35))
            let end = details.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.4 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture("10-season-two", app)
        XCTAssertTrue(episode.isHittable, "The loaded season's first episode is visible and usable")
        episode.tap()
        let close = app.buttons["Close player"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        defer { if close.exists { close.tap() } }
        let status = app.staticTexts["player-status"]
        let advancing = NSPredicate(format: "value MATCHES %@", "Playing, ([3-9]|[1-9][0-9]+) seconds elapsed")
        let playing = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: status)], timeout: 60) == .completed
        capture("10b-tv-episode-player", app)
        XCTAssertTrue(playing, "The selected Season 2 episode really plays")
        XCTAssertFalse(app.webViews.buttons["Cast to Device"].exists)
        // The portrait player lists the season from the episode cache the detail screen filled.
        XCTAssertTrue(app.buttons["Now playing: episode 1, Seven Thirty-Seven"].waitForExistence(timeout: 10),
                      "Up next shows the current season with the playing episode marked")
        let panel = app.scrollViews["player-info-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "The player's info panel is addressable")
        let nextEpisode = panel.buttons["Play episode 2, Grilled"].firstMatch
        XCTAssertTrue(nextEpisode.waitForExistence(timeout: 5))
        // Scroll only the portrait info panel (the video stage stays fixed), in short
        // steps toward the row's actual position: up when it is below the panel,
        // down when it is above. Whole-app swipes over-scrolled past it before.
        for _ in 0..<8 {
            let row = nextEpisode.frame
            let area = panel.frame
            if nextEpisode.isHittable, area.contains(row) { break }
            let below = row.maxY > area.maxY
            let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.65 : 0.35))
            let end = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.40 : 0.60))
            // Slow drag with a hold at the end: no fling momentum carrying past the row.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(nextEpisode.isHittable && panel.frame.contains(nextEpisode.frame),
                      "Episode 2 is fully inside the visible info panel: row \(nextEpisode.frame), panel \(panel.frame)")
        nextEpisode.tap()
        let switched = NSPredicate(format: "value CONTAINS %@", "path=/watch/tv/1396/2/2")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: switched, object: close)], timeout: 60), .completed,
                       "Up Next opens the requested episode in a fresh session")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: status)], timeout: 15), .completed,
                       "The next episode advances after the previous session is dismantled")
        capture("10c-next-tv-episode-player", app)
        let beforeServers = elapsed(status)
        app.buttons["Playback options"].tap()
        let chooseServer = app.buttons["Choose server"]
        XCTAssertTrue(chooseServer.waitForExistence(timeout: 5)); chooseServer.tap()
        let backToVideo = app.buttons["Back to video"].firstMatch
        XCTAssertTrue(backToVideo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.buttons["Fullscreen"].waitForExistence(timeout: 10),
                      "Provider controls become accessible when explicitly opened")
        capture("17-provider-controls", app)
        backToVideo.tap()
        XCTAssertTrue(app.buttons["Fullscreen"].waitForNonExistence(timeout: 5),
                      "Provider controls become inaccessible behind native video again")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: status)], timeout: 15), .completed)
        XCTAssertGreaterThanOrEqual(elapsed(status), beforeServers, "Returning from server controls preserves the native position")
        capture("17b-back-to-native-video", app)
    }

    /// AVKit's own fullscreen must keep the same AVPlayer: time keeps advancing through
    /// enter, rotation and exit, and the inline player is still usable afterwards.
    @MainActor func testAVKitFullscreenRoundTripKeepsPlayback() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Inception")
        let title = app.buttons["title-movie:27205"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap()
        let play = app.buttons["play-title"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        let close = app.buttons["Close player"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        defer {
            XCUIDevice.shared.orientation = .portrait
            if close.exists, close.isHittable { close.tap() }
        }
        let status = app.staticTexts["player-status"]
        let advancing = NSPredicate(format: "value MATCHES %@", "Playing, ([3-9]|[1-9][0-9]+) seconds elapsed")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: status)], timeout: 60), .completed,
                       "Inline playback starts before fullscreen is attempted")
        let before = elapsed(status)
        // Session and item identity before fullscreen; compared after each exit.
        let identityBefore = close.value as? String ?? ""
        XCTAssertNotNil(token("session", identityBefore), "Diagnostics expose the session identity: \(identityBefore)")

        // The native stage is addressable and the hidden public page is not:
        // its player controls must not be reachable behind the native video.
        let stage = app.otherElements["native-player-stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 5), "The native video stage is labelled for assistive technology and tests")
        XCTAssertFalse(app.buttons["Fullscreen"].exists, "The hidden website's Fullscreen control is not exposed")
        XCTAssertFalse(app.sliders["Seek Video"].exists, "The hidden website's scrubber is not exposed")

        // Enter through the app's always-visible native control (AVKit's inline
        // controls auto-hide, so they cannot be the only route).
        let enter = app.buttons["native-fullscreen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 5), "A native Full Screen control is present while playing")
        guard enter.exists, enter.isEnabled, enter.isHittable else {
            capture("16-fullscreen-control-missing", app)
            XCTFail("The native Full Screen control must be available; see the attached screenshot and accessibility hierarchy.")
            return
        }
        enter.tap()
        let covered = NSPredicate(format: "exists == false OR hittable == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: covered, object: close)], timeout: 8), .completed,
                       "The system fullscreen player covers the app chrome")
        sleep(2)
        capture("16-native-fullscreen", app)
        XCTAssertTrue(app.buttons["native-fullscreen-return"].isHittable, "Return control visible in portrait fullscreen")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(4)
        XCTAssertTrue(app.buttons["native-fullscreen-return"].isHittable, "Return control visible in landscape fullscreen")
        capture("16b-native-fullscreen-landscape", app)
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        // Leave with the app's own return control. It is always visible and owns
        // dismissal; the test never taps the video itself (that can hit play/pause).
        let returnControl = app.buttons["native-fullscreen-return"]
        XCTAssertTrue(returnControl.waitForExistence(timeout: 5) && returnControl.isHittable,
                      "The fullscreen return control is visible")
        returnControl.tap()
        let hittable = NSPredicate(format: "exists == true AND hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: close)], timeout: 10), .completed,
                       "The inline player and its close control return after fullscreen")
        XCTAssertTrue(stage.waitForExistence(timeout: 5), "The inline native stage is back")
        let progressed = NSPredicate(format: "value BEGINSWITH 'Playing, '")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: progressed, object: status)], timeout: 15), .completed,
                       "Playback is still running after leaving fullscreen")
        XCTAssertGreaterThanOrEqual(elapsed(status), before + 5, "The same AVPlayer kept its time through fullscreen (no restart from zero)")
        let diagnostics = close.value as? String ?? ""
        XCTAssertEqual(token("session", diagnostics), token("session", identityBefore), "Same playback session after fullscreen: \(diagnostics)")
        XCTAssertEqual(token("items", diagnostics), token("items", identityBefore), "Same AVPlayer item, no reload of the public page: \(diagnostics)")
        XCTAssertEqual(token("fsExit", diagnostics), "resumed", "The hand-back kept playing: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("external=false"), "External playback stays disabled: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("fullscreen=false"), "The session left fullscreen state: \(diagnostics)")
        XCTAssertFalse(app.buttons["Fullscreen"].exists, "The hidden website stays unexposed after fullscreen")
        capture("16c-after-fullscreen", app)

        // A pause made inside fullscreen survives leaving it, even when the user
        // returns immediately after pausing (no waiting window).
        let resumedTime = elapsed(status)
        XCTAssertTrue(enter.waitForExistence(timeout: 5) && enter.isHittable)
        enter.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: covered, object: close)], timeout: 8), .completed)
        let pause = app.buttons.matching(NSPredicate(format: "label ==[c] 'Pause'")).firstMatch
        if !(pause.exists && pause.isHittable) { revealFullscreenControls(app) }
        XCTAssertTrue(pause.waitForExistence(timeout: 3) && pause.isHittable, "AVKit's Pause control is reachable in fullscreen")
        pause.tap()
        XCTAssertTrue(returnControl.isHittable)
        returnControl.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: close)], timeout: 10), .completed)
        let pausedValue = NSPredicate(format: "value BEGINSWITH 'Paused, '")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: pausedValue, object: status)], timeout: 5), .completed,
                       "A user pause inside fullscreen stays paused after an immediate return")
        let pausedAt = status.value as? String ?? ""
        XCTAssertGreaterThanOrEqual(elapsed(status), resumedTime, "Same player time after the paused round trip (no restart)")
        // Observe that nothing resumes it: the value must not change within 3 s.
        let changed = NSPredicate(format: "value != %@", pausedAt)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: status)], timeout: 3), .timedOut,
                       "Playback is not resumed behind the user's back")
        let pausedDiagnostics = close.value as? String ?? ""
        XCTAssertEqual(token("fsExit", pausedDiagnostics), "kept-paused", pausedDiagnostics)
        XCTAssertEqual(token("session", pausedDiagnostics), token("session", identityBefore), pausedDiagnostics)
        XCTAssertEqual(token("items", pausedDiagnostics), token("items", identityBefore), pausedDiagnostics)
        XCTAssertTrue(pausedDiagnostics.contains("fullscreen=false") && pausedDiagnostics.contains("external=false"), pausedDiagnostics)
        capture("16d-after-fullscreen-paused", app)
    }

    /// AVKit's controls auto-hide. Reveal them with a tap on empty letterbox space,
    /// well away from play/pause and skip controls and from the return control.
    @MainActor private func revealFullscreenControls(_ app: XCUIApplication) {
        let player = app.otherElements["native-fullscreen-player"]
        let surface = player.exists ? player : app.windows.firstMatch
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }

    /// Reads `key=value` from the player's diagnostics string.
    private func token(_ key: String, _ diagnostics: String) -> String? {
        diagnostics.split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    @MainActor func testSettingsAppearance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let theme = app.buttons["appearance-picker"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5)); theme.tap()
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 5))
        capture("13a-theme-menu", app)
        app.buttons["Dark"].tap()
        capture("13-settings-dark", app)
        theme.tap(); app.buttons["Light"].tap()
        capture("14-settings-light", app)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["History"].tap()
        capture("15-history-overview", app)
    }

    @MainActor func testPlaybackHistoryAndNoCasting() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Inception")
        let title = app.buttons["title-movie:27205"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap()
        // The detail button reads "Play" or "Resume…" depending on local history.
        let play = app.buttons["play-title"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        defer { if app.buttons["Close player"].exists { app.buttons["Close player"].tap() } }
        let status = app.staticTexts["player-status"]
        let advancing = NSPredicate(format: "value MATCHES %@", "Playing, ([3-9]|[1-9][0-9]+) seconds elapsed")
        let playing = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: status)], timeout: 60) == .completed
        capture("11-player", app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "Landscape layout has settled")
        XCTAssertTrue(app.buttons["Close player"].isHittable)
        XCTAssertTrue(app.buttons["Save to Library"].isHittable)
        capture("11b-player-landscape", app)
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(playing, "The real video clock advances for at least three seconds")
        let initialValue = status.value as? String ?? ""
        let progresses = NSPredicate(format: "value BEGINSWITH %@ AND value != %@", "Playing, ", initialValue)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: progresses, object: status)], timeout: 10), .completed, "Playback continues advancing after the initial report")
        XCTAssertFalse(app.webViews.buttons["Cast to Device"].exists)
        sleep(8)
        let savedSeconds = elapsed(status)
        XCTAssertGreaterThanOrEqual(savedSeconds, 3)
        app.buttons["Close player"].tap()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["History"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Inception").firstMatch.waitForExistence(timeout: 10))
        capture("12-watch-history", app)
        app.buttons.containing(.staticText, identifier: "Inception").firstMatch.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        let resumedStatus = app.staticTexts["player-status"]
        let resumed = NSPredicate(format: "value BEGINSWITH %@", "Playing, ")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: resumedStatus)], timeout: 60), .completed)
        XCTAssertGreaterThanOrEqual(elapsed(resumedStatus), savedSeconds - 2, "The first playing report resumes the saved position instead of restarting at zero")
        capture("12b-resumed-player", app)
        app.buttons["Close player"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let clear = app.buttons["clear-history"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); XCTAssertTrue(clear.isEnabled)
        clear.tap()
        let confirm = app.buttons["Clear history"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("12c-clear-confirmation", app)
        confirm.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Pick up where you left off"].waitForExistence(timeout: 5))
        capture("12c-cleared-history", app)
    }

    @MainActor private func elapsed(_ element: XCUIElement) -> Int {
        let value = element.value as? String ?? ""
        let time = value.components(separatedBy: ", ").last ?? ""
        return Int(time.components(separatedBy: " ").first ?? "") ?? -1
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        // Capture the physical screen. App-element screenshots can crop with a
        // stale portrait coordinate transform after Simulator rotation.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if name.hasPrefix("16") {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "\(name)-accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        if name.hasPrefix("11-") || name == "10b-tv-episode-player" {
            let diagnostics = app.buttons["Close player"].value as? String ?? "No media diagnostics"
            print("Cinejoy media state: \(diagnostics)")
            let state = XCTAttachment(string: diagnostics)
            state.name = "\(name)-media-state"
            state.lifetime = .keepAlways
            add(state)
        }
    }
}
