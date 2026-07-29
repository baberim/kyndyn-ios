import XCTest

@MainActor
final class KyndynUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(
        parentUnlocked: Bool = false,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-cloud-unconfigured"
        ]
            + (parentUnlocked ? ["-ui-testing-parent-unlocked"] : [])
            + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["Create a sample household"].waitForExistence(timeout: 8))
        app.buttons["Create a sample household"].tap()
        return app
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Expected \(label) navigation item")
        item.tap()
    }

    func testOnboardingProfileAndQuestJourney() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        tapTab("Quests", in: app)
        let toggle = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertTrue(app.buttons["Undo Make your bed"].waitForExistence(timeout: 3))
        app.buttons["Undo Make your bed"].tap()
        XCTAssertTrue(app.buttons["Complete Make your bed"].waitForExistence(timeout: 3))
    }

    func testParentAreaRequiresAuthentication() throws {
        let app = launch()
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        XCTAssertTrue(app.staticTexts["Parent area"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Use Face ID, Touch ID, or passcode"].exists)
        XCTAssertFalse(app.staticTexts["People"].exists)
    }

    func testParentCanCreatePersonAndQuestWhenAuthenticated() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        XCTAssertTrue(app.staticTexts["People"].waitForExistence(timeout: 3))
        app.staticTexts["People"].tap()
        app.buttons["Add"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Casey")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Casey"].waitForExistence(timeout: 3))
    }

    func testParentCanReviewLocalOnlyFamilySyncStatus() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        XCTAssertTrue(app.staticTexts["Family sync"].waitForExistence(timeout: 3))
        app.staticTexts["Family sync"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cloud-sync-settings"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["cloud-configuration-readiness"]
            .waitForExistence(timeout: 3))
    }

    func testAdaptiveDashboardSupportsLandscapeDarkModeAndLargeText() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(additionalArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        tapTab("Quests", in: app)
        let questAction = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(questAction.waitForExistence(timeout: 3))
        if !questAction.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(questAction.isHittable, "Quest action should remain reachable in the constrained layout")
    }

    func testHouseholdPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-persistence-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Create a sample household"].waitForExistence(timeout: 8))
        app.buttons["Create a sample household"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Create a sample household"].exists)
    }
}
