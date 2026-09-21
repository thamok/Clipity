import XCTest

final class BackgroundCaptureTests: XCTestCase {
    @MainActor
    func testBackgroundChangeCanBeSavedFromNotification() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Private background clipboard behavior requires a physical device.")
        #else
            let app = XCUIApplication()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            app.launch()
            allowPasteIfPresented()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
            app.buttons["Settings"].tap()
            let automatic = app.switches["automaticCapture"]
            XCTAssertTrue(automatic.waitForExistence(timeout: 5))
            if automatic.value as? String == "0" { automatic.tap() }
            app.swipeUp()
            let notifications = app.switches["Clipboard notifications"]
            if notifications.exists && notifications.value as? String == "0" { notifications.tap() }
            app.buttons["Enable Notifications"].tap()
            if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
            app.swipeDown()
            let background = app.switches["backgroundMonitoring"]
            XCTAssertTrue(background.waitForExistence(timeout: 5))
            if background.value as? String == "0" {
                background.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            if springboard.buttons["Allow While Using App"].waitForExistence(timeout: 5) {
                springboard.buttons["Allow While Using App"].tap()
            }
            if springboard.buttons["Change to Always Allow"].waitForExistence(timeout: 3) {
                springboard.buttons["Change to Always Allow"].tap()
            }
            XCTAssertEqual(background.value as? String, "1", "Background monitoring must remain enabled")
            let settingsProof = XCTAttachment(screenshot: app.screenshot())
            settingsProof.name = "Physical background monitoring setup"
            settingsProof.lifetime = .keepAlways
            add(settingsProof)
            app.buttons["Done"].tap()

            let text = "Physical background clipboard proof \(UUID().uuidString)"
            let source = XCUIApplication(bundleIdentifier: "de.thamo.clipity.testsource")
            source.launchArguments = ["--clip-proof", text]
            source.launch()
            XCTAssertTrue(source.buttons["Copy Test Clipping"].waitForExistence(timeout: 10))
            source.buttons["Copy Test Clipping"].tap()
            let pending = springboard.staticTexts["Clipboard Changed"].firstMatch
            let banner = springboard.staticTexts.matching(
                NSPredicate(format: "label IN %@", ["Clipboard Changed", "Clipping Saved"])
            ).firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 15))
            if pending.exists {
                pending.press(forDuration: 1.5)
                if springboard.buttons["Allow Paste"].waitForExistence(timeout: 3) {
                    springboard.buttons["Allow Paste"].tap()
                }
            }
            if pending.exists {
                // The extension shows this only after committing to shared storage.
                XCTAssertTrue(springboard.staticTexts["Saved to Clipity history."].waitForExistence(timeout: 10))
            }
            let notificationProof = XCTAttachment(screenshot: springboard.screenshot())
            notificationProof.name = "Physical background notification capture"
            notificationProof.lifetime = .keepAlways
            add(notificationProof)
            app.activate()
            if springboard.buttons["Allow Paste"].waitForExistence(timeout: 3) {
                springboard.buttons["Allow Paste"].tap()
            }
            XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 10))
        #endif
    }
}
