import XCTest

#if targetEnvironment(simulator)
    import AppIntents
    import AppIntentsTesting

    @available(iOS 27.0, *)
    final class ClipIntentTests: XCTestCase {
        @MainActor
        func testAddFindKeepRetrieveAndOpen() async throws {
            let app = XCUIApplication()
            app.launch()
            allowPasteIfPresented()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
            let definitions = IntentDefinitions(bundleIdentifier: "de.thamo.clipity")
            let title = "Shortcut integration \(UUID().uuidString)"
            let text = "A clipping created through the real App Intents execution pipeline."
            let added = try await definitions.intents["AddClippingIntent"].makeIntent(
                text: text, title: title, keep: false
            ).run()
            XCTAssertEqual(try added.value.as(String.self), text)

            let queried = try await definitions.entities["ClippingEntity"].entities(matching: title)
            let entity = try XCTUnwrap(queried.first)
            XCTAssertEqual(queried.count, 1)
            XCTAssertEqual(try entity.text, text)

            let found = try await definitions.intents["FindClippingsIntent"].makeIntent(
                search: title, count: 500, savedOnly: false
            ).run()
            let matches: [AnyAppEntity] = try found.value
            XCTAssertEqual(matches.count, 1)

            let kept = try await definitions.intents["KeepClippingIntent"].makeIntent(clipping: entity).run()
            XCTAssertEqual(try kept.value.saved, true)
            let fileResult = try await definitions.intents["GetClippingFileIntent"].makeIntent(clipping: entity).run()
            let file: IntentFile = try fileResult.value
            XCTAssertEqual(String(data: file.data, encoding: .utf8), text)

            try await definitions.intents["OpenClippingIntent"].makeIntent(target: entity).run()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Share"].exists)
        }

    }
#endif

final class ClipCaptureUITests: XCTestCase {
    @MainActor
    func testAutomaticCaptureAndReopen() throws {
        let app = XCUIApplication()
        app.launch()
        allowPasteIfPresented()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let toggle = app.switches["automaticCapture"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "0" { toggle.tap() }
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        let text = "Automatic clipboard proof \(UUID().uuidString)"
        UIPasteboard.general.string = text
        allowPasteIfPresented()
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        allowPasteIfPresented()
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Automatically captured history survives relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
func allowPasteIfPresented() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.buttons["Allow Paste"].waitForExistence(timeout: 3) { springboard.buttons["Allow Paste"].tap() }
}
