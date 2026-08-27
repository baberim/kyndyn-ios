import XCTest

@MainActor
final class KyndynUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        skipIntroduction(in: app)
        XCTAssertTrue(app.buttons["Explore with sample data"].waitForExistence(timeout: 8))
        app.buttons["Explore with sample data"].tap()
        return app
    }

    private func skipIntroduction(in app: XCUIApplication) {
        let skip = app.buttons["Skip introduction"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
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
        app.buttons["quest-status-filter"].tap()
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

    func testFirstRunExplainsSetupBeforeShowingChoices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-cloud-unconfigured"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Small quests. Shared progress."]
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Set up my family"].exists)
        for _ in 0..<3 { app.buttons["onboarding-next"].tap() }
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.buttons["Set up my family"].waitForExistence(timeout: 3))
    }

    func testHomeUsesUnifiedProgressAndHidesEmptyActivity() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home-profile-scene"]
            .waitForExistence(timeout: 5))
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
        tapTab("Settings", in: app)
        app.buttons["settings-app-icon"].tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["app-icon-original"].exists)
        XCTAssertTrue(app.buttons["app-icon-pastel"].exists)
        app.navigationBars["App icon"].buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-app-color"].exists)
        XCTAssertTrue(app.buttons["settings-companion"].exists)
        XCTAssertTrue(app.buttons["settings-background"].exists)
        app.buttons["settings-app-color"].tap()
        XCTAssertTrue(app.navigationBars["App color"]
            .waitForExistence(timeout: 3))
        let teal = app.buttons["Teal profile color"]
        reveal(teal, in: app)
        teal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-custom-color"].exists)
        app.buttons["Save"].tap()
        app.buttons["settings-companion"].tap()
        XCTAssertTrue(app.navigationBars["Companion"]
            .waitForExistence(timeout: 3))
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Orbit")
        ).firstMatch.tap()
        app.buttons["Save"].tap()
        tapTab("Home", in: app)
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 3))
    }

    func testSettingsExplainsSiriAndShortcutsPrivacy() throws {
        let app = launch()
        tapTab("Settings", in: app)
        let siriHelp = app.buttons["settings-siri-shortcuts"]
        reveal(siriHelp, in: app)
        siriHelp.tap()
        XCTAssertTrue(app.navigationBars["Siri & Shortcuts"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["“Show today’s Kyndyn quests”"].exists)
        let privacyCopy = app.descendants(matching: .any)[
            "siri-shortcuts-privacy"]
        reveal(privacyCopy, in: app)
        XCTAssertTrue(privacyCopy.exists)
    }

    func testEmptyOnboardingOffersNonDestructiveICloudRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-cloud-unconfigured"
        ]
        app.launch()
        skipIntroduction(in: app)
        XCTAssertTrue(app.buttons["Restore or import a household"]
            .waitForExistence(timeout: 8))
        app.buttons["Restore or import a household"].tap()
        XCTAssertTrue(app.buttons["Restore from iCloud"]
            .waitForExistence(timeout: 3))
        app.buttons["Restore from iCloud"].firstMatch.tap()
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
        skipIntroduction(in: app)
        XCTAssertTrue(app.buttons["Set up my family"]
            .waitForExistence(timeout: 8))
        app.buttons["Set up my family"].tap()
        let household = app.textFields["Household name"]
        XCTAssertTrue(household.waitForExistence(timeout: 3))
        household.tap(); household.typeText("Fictional Pilot Family")
        let parent = app.textFields["Parent name"]
        parent.tap(); parent.typeText("Taylor")
        app.buttons["Create family"].tap()
        XCTAssertTrue(app.navigationBars["Family setup guide"]
            .waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Taylor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Maya"].exists)
        XCTAssertFalse(app.staticTexts["Leo"].exists)
        XCTAssertFalse(app.staticTexts["Zoe"].exists)
    }

    func testParentAreaRequiresAuthentication() throws {
        let app = launch()
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        XCTAssertTrue(app.staticTexts["Parent area"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Use Face ID, Touch ID, or passcode"].exists)
        XCTAssertFalse(app.staticTexts["People"].exists)
    }

    func testParentCanCreatePersonAndQuestWhenAuthenticated() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familyTools = app.buttons["Family and quests"]
        reveal(familyTools, in: app)
        familyTools.tap()
        let people = app.buttons.matching(
            NSPredicate(format: "label == %@", "People")
        ).firstMatch
        reveal(people, in: app)
        XCTAssertTrue(people.waitForExistence(timeout: 3))
        people.tap()
        app.buttons["Add"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Casey")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Casey"].waitForExistence(timeout: 3))
    }

    func testParentCanBrowseScheduleAndStartFromTemplate() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familyTools = app.buttons["Family and quests"]
        reveal(familyTools, in: app)
        familyTools.tap()
        let planning = app.staticTexts["Quest planning"]
        reveal(planning, in: app)
        planning.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quest-planning"]
            .waitForExistence(timeout: 3))
        app.staticTexts["Quest templates"].tap()
        let template = app.buttons["quest-template-morning-routine"]
        XCTAssertTrue(template.waitForExistence(timeout: 3))
        template.tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Morning Routine")
        app.buttons["Cancel"].tap()
        app.navigationBars["Quest templates"].buttons["Quest planning"].tap()
        app.staticTexts["Two-week schedule"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quest-schedule-overview"]
            .waitForExistence(timeout: 3))
    }

    func testParentCanRunPrivacySafeHouseholdSafetyCheck() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let devicePrivacy = app.buttons["Device and privacy"]
        reveal(devicePrivacy, in: app)
        devicePrivacy.tap()
        let dataAndPrivacy = app.buttons.matching(
            NSPredicate(format: "label == %@", "Backup and family data")
        ).firstMatch
        reveal(dataAndPrivacy, in: app)
        dataAndPrivacy.tap()
        XCTAssertTrue(app.navigationBars["Backup and family data"]
            .waitForExistence(timeout: 3))
        let check = app.buttons["run-household-safety-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 3))
        check.tap()
        XCTAssertTrue(app.staticTexts["Household"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Active profiles"].exists)
        XCTAssertTrue(app.staticTexts["Waiting to sync"].exists)
    }

    func testProfileColorSelectionDoesNotFallThroughToOrange() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familyTools = app.buttons["Family and quests"]
        reveal(familyTools, in: app)
        familyTools.tap()
        let people = app.buttons.matching(
            NSPredicate(format: "label == %@", "People")
        ).firstMatch
        reveal(people, in: app)
        people.tap()
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
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let familySync = app.buttons["parent-family-sync"]
        reveal(familySync, in: app)
        familySync.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cloud-sync-settings"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["cloud-configuration-readiness"]
            .waitForExistence(timeout: 3))
    }

    func testParentCanEditAndRestartFamilyReward() throws {
        let app = launch(parentUnlocked: true)
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        tapTab("Parent", in: app)
        let rewards = app.buttons["Rewards and progress"]
        reveal(rewards, in: app)
        rewards.tap()
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
        let updated = app.staticTexts["Family reward updated."]
        reveal(updated, in: app)
        XCTAssertTrue(updated.waitForExistence(timeout: 3))

        app.buttons["Start as a new reward"].tap()
        XCTAssertTrue(app.alerts["Start a new family reward?"]
            .waitForExistence(timeout: 3))
        app.alerts.buttons["Start at 0 XP"].tap()
        let restarted = app.staticTexts["New reward started at 0 XP."]
        reveal(restarted, in: app)
        XCTAssertTrue(restarted.waitForExistence(timeout: 3))
        let history = app.staticTexts["Reward history"]
        reveal(history, in: app)
        XCTAssertTrue(history.exists)
    }

    func testAdaptiveDashboardSupportsPortraitDarkModeAndLargeText() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(additionalArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        XCTAssertTrue(app.staticTexts["Hi, Leo"].waitForExistence(timeout: 5))
        tapTab("Quests", in: app)
        app.buttons["quest-status-filter"].tap()
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "All")
        ).firstMatch.tap()
        let questAction = app.buttons["quest-toggle-Make your bed"]
        XCTAssertTrue(questAction.waitForExistence(timeout: 3))
        reveal(questAction, in: app)
        XCTAssertTrue(questAction.isHittable,
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
        skipIntroduction(in: app)
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
        skipIntroduction(in: app)
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
        tapTab("Profiles", in: app)
        app.buttons["profile-Maya"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Maya"].waitForExistence(timeout: 5))
    }
}
