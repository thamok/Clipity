import XCTest

final class ClipityUITests: XCTestCase {
    @MainActor
    func testCreatePermanentClippingAndDarkAppearance() throws {
        let app = XCUIApplication()
        let clippingTitle = "Device save \(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-appearance", "dark"]
        app.launch()
        allowPasteIfPresented()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15))
        app.buttons["History"].press(forDuration: 0.6)
        XCTAssertFalse(app.alerts["Couldn’t complete that"].exists)
        app.buttons["Write a clipping"].tap()
        let title = app.textFields["Title (optional)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        title.typeText(clippingTitle)
        XCTAssertEqual(title.value as? String, clippingTitle)
        let editor = app.textViews["Clipping text"]
        editor.tap()
        editor.typeText("Remember to visit the museum this weekend.")
        XCTAssertEqual(editor.value as? String, "Remember to visit the museum this weekend.")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["collectionPicker"].tap()
        app.buttons["All saved"].tap()
        XCTAssertTrue(app.staticTexts[clippingTitle].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        allowPasteIfPresented()
        XCTAssertTrue(app.buttons["collectionPicker"].waitForExistence(timeout: 15))
        app.buttons["collectionPicker"].tap()
        app.buttons["All saved"].tap()
        XCTAssertTrue(app.staticTexts[clippingTitle].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Saved clipping in dark appearance"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.staticTexts[clippingTitle].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Remember to visit the museum this weekend."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].exists)
        app.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5))
    }
}
