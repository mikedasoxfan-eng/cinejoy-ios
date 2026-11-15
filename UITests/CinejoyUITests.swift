import XCTest

final class CinejoyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testNativeBrowsingAndLocalLibrary() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CINEJOY_UI_TESTS"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["Cinejoy"].waitForExistence(timeout: 15))
        capture("01-home", app)

        app.tabBars.buttons["Browse"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        capture("02-browse", app)
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

        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
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
        field.tap(); field.typeText("Inception")
        XCTAssertTrue(app.buttons["title-movie:27205"].waitForExistence(timeout: 30))
        capture("07-live-search", app)
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "zzzzcinejoynomatch999")
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
        let seasonMenu = app.buttons["Season 1"]
        XCTAssertTrue(seasonMenu.waitForExistence(timeout: 30))
        capture("09-tv-episodes", app)
        seasonMenu.tap()
        let secondSeason = app.buttons["Season 2"]
        XCTAssertTrue(secondSeason.waitForExistence(timeout: 5)); secondSeason.tap()
        XCTAssertTrue(app.buttons["Play episode 1, Seven Thirty-Seven"].waitForExistence(timeout: 30))
        capture("10-season-two", app)
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
        let pause = app.webViews.buttons["Pause"].firstMatch
        let playing = pause.waitForExistence(timeout: 45)
        capture("11-player", app)
        XCTAssertTrue(playing, "The real Cinejoy player reaches active playback")
        XCTAssertFalse(app.webViews.buttons["Cast to Device"].exists)
        sleep(8)
        app.buttons["Close player"].tap()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["History"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Inception").firstMatch.waitForExistence(timeout: 10))
        capture("12-watch-history", app)
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
