import XCTest

final class CinejoyUITests: XCTestCase {
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

        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Odyssey")
        XCTAssertTrue(app.buttons["title-movie:1368337"].waitForExistence(timeout: 8))
        capture("05-native-search", app)

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("06-settings", app)
        XCTAssertFalse(app.buttons["Log in"].exists)
        XCTAssertFalse(app.buttons["Sign up"].exists)
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
