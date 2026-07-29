import XCTest

final class RowanUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnboardingProfileAndQuestJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        if app.buttons["Create a sample household"].waitForExistence(timeout: 3) {
            app.buttons["Create a sample household"].tap()
        }
        if app.buttons["profile-Leo"].waitForExistence(timeout: 3) {
            app.buttons["profile-Leo"].tap()
        }
        app.tabBars.buttons["Quests"].tap()
        let toggle = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertTrue(app.buttons["Undo Make your bed"].waitForExistence(timeout: 3))
        app.buttons["Undo Make your bed"].tap()
    }
}

