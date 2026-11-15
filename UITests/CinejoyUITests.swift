import XCTest

final class CinejoyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
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

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'title-'")).firstMatch.waitForExistence(timeout: 5))
        capture("04-local-library", app)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'title-'")).firstMatch.waitForExistence(timeout: 5), "Saved titles survive a full app relaunch")

        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
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
        XCTAssertTrue(secondSeason.waitForExistence(timeout: 5)); secondSeason.tap()
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
    }

    @MainActor func testSettingsAppearance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let theme = app.buttons["appearance-picker"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5)); theme.tap()
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
        let play = app.buttons["Play"].firstMatch
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
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if name.hasPrefix("11-") {
            let state = XCTAttachment(string: app.buttons["Close player"].value as? String ?? "No media diagnostics")
            state.name = "\(name)-media-state"
            state.lifetime = .keepAlways
            add(state)
        }
    }
}
