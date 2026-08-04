import XCTest

@MainActor
final class KyndynUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

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
        XCTAssertTrue(app.buttons["Explore with sample data"].waitForExistence(timeout: 8))
        app.buttons["Explore with sample data"].tap()
        return app
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Expected \(label) navigation item")
        item.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists)
    }

    func testOnboardingProfileAndQuestJourney() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        tapTab("Quests", in: app)
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "All")
        ).firstMatch.tap()
        let toggle = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertTrue(app.buttons["Undo Make your bed"].waitForExistence(timeout: 3))
        app.buttons["Undo Make your bed"].tap()
        XCTAssertTrue(app.buttons["Complete Make your bed"].waitForExistence(timeout: 3))
    }

    func testHomeUsesUnifiedProgressAndHidesEmptyActivity() throws {
        let app = launch()
        let progress = app.descendants(matching: .any)["home-progress-summary"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent activity"].exists)

        progress.tap()
        XCTAssertTrue(app.navigationBars["Leo’s progress"]
            .waitForExistence(timeout: 3))
    }

    func testQuestBrowsingFiltersSearchAndDetails() throws {
        let app = launch()
        tapTab("Quests", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quest-status-filter"]
            .waitForExistence(timeout: 3))
        let search = app.searchFields["Search quests"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("bed")
        XCTAssertTrue(app.buttons["Details for Make your bed"]
            .waitForExistence(timeout: 3))
        app.buttons["Details for Make your bed"].tap()
        XCTAssertTrue(app.staticTexts["Completion history"]
            .waitForExistence(timeout: 3))
    }

    func testActivePersonCanCustomizeProfileWithoutParentTools() throws {
        let app = launch()
        app.buttons["My profile"].tap()
        XCTAssertTrue(app.navigationBars["My profile"]
            .waitForExistence(timeout: 3))
        app.buttons["Teal profile color"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-custom-color"].exists)
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Orbit")
        ).firstMatch.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 3))
    }

    func testEmptyOnboardingOffersNonDestructiveICloudRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Bring back my family"]
            .waitForExistence(timeout: 8))
        app.buttons["Bring back my family"].tap()
        XCTAssertTrue(app.buttons["Recover from iCloud"]
            .waitForExistence(timeout: 3))
        app.buttons["Recover from iCloud"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Recover from iCloud"]
            .waitForExistence(timeout: 3))
    }

    func testRealFamilySetupCreatesNoSampleRecords() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Set up my family"]
            .waitForExistence(timeout: 8))
        app.buttons["Set up my family"].tap()
        let household = app.textFields["Household name"]
        XCTAssertTrue(household.waitForExistence(timeout: 3))
        household.tap(); household.typeText("Fictional Pilot Family")
        let parent = app.textFields["Parent name"]
        parent.tap(); parent.typeText("Taylor")
        app.buttons["Create family"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Taylor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Maya"].exists)
        XCTAssertFalse(app.staticTexts["Leo"].exists)
        XCTAssertFalse(app.staticTexts["Zoe"].exists)
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

    func testProfileColorSelectionDoesNotFallThroughToOrange() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        app.staticTexts["People"].tap()
        app.buttons["Add"].tap()
        let teal = app.buttons["profile-color-#00A6A6"]
        XCTAssertTrue(teal.waitForExistence(timeout: 3))
        teal.tap()
        XCTAssertEqual(teal.value as? String, "Selected")
        XCTAssertEqual(app.buttons["profile-color-#FF9500"].value as? String,
                       "Not selected")
        XCTAssertTrue(app.descendants(matching: .any)["profile-custom-color"].exists)
    }

    func testParentCanReviewLocalOnlyFamilySyncStatus() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familySync = app.staticTexts["Family sync"]
        reveal(familySync, in: app)
        familySync.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cloud-sync-settings"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["cloud-configuration-readiness"]
            .waitForExistence(timeout: 3))
    }

    func testParentCanEditAndRestartFamilyReward() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familyReward = app.staticTexts["Family reward"]
        reveal(familyReward, in: app)
        familyReward.tap()

        let title = app.textFields["Reward name"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                              count: 40))
        title.typeText("Fictional Aquarium Trip")

        let target = app.textFields["Goal XP"]
        target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                               count: 10))
        target.typeText("450")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.staticTexts["Family reward updated."]
            .waitForExistence(timeout: 3))

        app.buttons["Start as a new reward"].tap()
        XCTAssertTrue(app.alerts["Start a new family reward?"]
            .waitForExistence(timeout: 3))
        app.alerts.buttons["Start at 0 XP"].tap()
        XCTAssertTrue(app.staticTexts["New reward started at 0 XP."]
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
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "All")
        ).firstMatch.tap()
        let questAction = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(questAction.waitForExistence(timeout: 3))
        questAction.tap()
        XCTAssertTrue(app.buttons["Undo Make your bed"].waitForExistence(timeout: 3),
                      "Quest action should remain usable in the constrained layout")
    }

    func testHouseholdPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-persistence-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Explore with sample data"].waitForExistence(timeout: 8))
        app.buttons["Explore with sample data"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Explore with sample data"].exists)
    }

    func testWholeHouseholdModePersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-persistence-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Explore with sample data"]
            .waitForExistence(timeout: 8))
        app.buttons["Explore with sample data"].tap()
        let everyone = app.buttons["Everyone"]
        XCTAssertTrue(everyone.waitForExistence(timeout: 3))
        everyone.tap()
        XCTAssertTrue(app.staticTexts["Everyone’s day"]
            .waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = [
            "-ui-testing-persistence",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Everyone’s day"]
            .waitForExistence(timeout: 8))

        app.buttons["My day"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        tapTab("Switch", in: app)
        app.buttons["profile-Maya"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Maya"].waitForExistence(timeout: 5))
    }
}
