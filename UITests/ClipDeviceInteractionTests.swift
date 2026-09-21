import XCTest

final class ClipDeviceInteractionTests: XCTestCase {
    @MainActor
    func testFullSwipeCopiesWithoutClosingApp() throws {
        let app = XCUIApplication()
        app.launch()
        allowPasteIfPresented()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15))
        app.buttons["History"].press(forDuration: 0.8)
        app.buttons["Write a clipping"].tap()
        let text = "Full swipe proof \(UUID().uuidString.prefix(8))"
        let editor = app.textViews["Clipping text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(text)
        app.switches["Keep permanently"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Save"].tap()
        let row = app.cells.containing(.staticText, identifier: text).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(row.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Full swipe copy without a crash"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testGenerateTitleWhenModelIsAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        allowPasteIfPresented()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15))
        app.buttons["History"].press(forDuration: 0.8)
        app.buttons["Write a clipping"].tap()
        let editor = app.textViews["Clipping text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Pack walking shoes and a rain jacket for the weekend trip to the mountains.")
        app.buttons["Generate title"].tap()
        let title = app.textFields["Title (optional)"]
        let completed = NSPredicate { _, _ in
            let value = title.value as? String ?? ""
            return (!value.isEmpty && value != "Title (optional)") || app.alerts.firstMatch.exists
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: completed, object: nil)], timeout: 60)
        XCTAssertEqual(result, .completed)
        if app.alerts.firstMatch.exists {
            let message = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            if message.contains("Enable Apple Intelligence") {
                throw XCTSkip("On-device model unavailable: availability message verified")
            }
            XCTFail(message)
        } else {
            XCTAssertFalse((title.value as? String ?? "").isEmpty)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Generated title on device"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
