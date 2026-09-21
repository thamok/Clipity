import XCTest

#if targetEnvironment(simulator)
    import AppIntents
    import AppIntentsTesting

    @available(iOS 27.0, *)
    final class ClipInteractionTests: XCTestCase {
        @MainActor
        func testNavigationOrderCollapseAndSearch() async throws {
            let app = XCUIApplication()
            app.launch()
            allowPasteIfPresented()
            let definitions = IntentDefinitions(bundleIdentifier: "de.thamo.clipity")
            for index in 0..<14 {
                _ = try await definitions.intents["AddClippingIntent"].makeIntent(
                    text: "Scroll proof \(index) \(UUID().uuidString.prefix(8))", keep: false
                ).run()
            }
            let folders = app.buttons["collectionPicker"]
            let home = app.buttons["History"]
            let search = app.buttons["Search"]
            let settings = app.buttons["Settings"]
            XCTAssertLessThan(folders.frame.midX, home.frame.midX)
            XCTAssertLessThan(home.frame.midX, search.frame.midX)
            XCTAssertLessThan(search.frame.midX, settings.frame.midX)
            app.swipeUp()
            XCTAssertTrue(app.buttons["Show navigation"].waitForExistence(timeout: 5))
            XCTAssertLessThan(app.buttons["Show navigation"].frame.midX, app.frame.width * 0.3)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Navigation collapsed to the left"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons["Show navigation"].tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            search.tap()
            app.textFields["clippingSearch"].typeText("Scroll proof")
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Scroll proof")).firstMatch.exists)
        }

        @MainActor
        func testHomeScreenActionsWarmAndColdLaunch() async throws {
            let app = XCUIApplication()
            app.launch()
            allowPasteIfPresented()
            let definitions = IntentDefinitions(bundleIdentifier: "de.thamo.clipity")
            _ = try await definitions.intents["AddClippingIntent"].makeIntent(
                text: "Home Screen action proof", keep: false
            ).run()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            func openMenu() {
                XCUIDevice.shared.press(.home)
                var visible: XCUIElement?
                for _ in 0..<4 {
                    let ready = NSPredicate { _, _ in
                        springboard.icons.matching(identifier: "Clipity").allElementsBoundByIndex.contains {
                            $0.isHittable && $0.frame.width > 0
                        }
                    }
                    _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 2)
                    visible = springboard.icons.matching(identifier: "Clipity").allElementsBoundByIndex.first {
                        $0.isHittable && $0.frame.width > 0
                    }
                    if visible != nil { break }
                    springboard.swipeLeft()
                }
                guard let visible else {
                    XCTFail("Clipity icon was not visible on the Home Screen")
                    return
                }
                visible.press(forDuration: 0.8)
            }
            func action(_ title: String) -> XCUIElement {
                let identifiers = [
                    "Add Clip with AI": "de.thamo.clipity.add-ai", "Add Clip": "de.thamo.clipity.add",
                    "Get Last Clip": "de.thamo.clipity.latest", "Show Last 3 Clips": "de.thamo.clipity.recent",
                ]
                return springboard.buttons[identifiers[title]!]
            }
            openMenu()
            for title in ["Add Clip with AI", "Add Clip", "Get Last Clip", "Show Last 3 Clips"] {
                XCTAssertTrue(action(title).waitForExistence(timeout: 5))
            }
            let attachment = XCTAttachment(screenshot: springboard.screenshot())
            attachment.name = "Home Screen quick actions"
            attachment.lifetime = .keepAlways
            add(attachment)
            action("Show Last 3 Clips").tap()
            XCTAssertTrue(app.navigationBars["Last 3 clips"].waitForExistence(timeout: 10))
            app.terminate()
            openMenu()
            action("Get Last Clip").tap()
            XCTAssertTrue(app.navigationBars["Clipping"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Home Screen action proof"].exists)
        }

        @MainActor
        func testSwipeOrganizeShareAndNavigation() async throws {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", "dark"]
            app.launch()
            allowPasteIfPresented()
            let definitions = IntentDefinitions(bundleIdentifier: "de.thamo.clipity")
            let text = "Gesture proof \(UUID().uuidString.prefix(8))"
            _ = try await definitions.intents["AddClippingIntent"].makeIntent(text: text, keep: false).run()
            let row = app.cells.containing(.staticText, identifier: text).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))

            row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
            XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 5))
            row.swipeLeft()
            XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
            app.buttons["Organize"].tap()
            XCTAssertTrue(app.navigationBars["Organize clipping"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.switches["Keep permanently"].value as? String, "1")
            XCTAssertTrue(app.buttons["Generate title"].exists)
            XCTAssertTrue(app.buttons["folderPicker"].exists)
            let folder = "Gesture folder \(UUID().uuidString.prefix(6))"
            app.textFields["New folder"].tap()
            app.textFields["New folder"].typeText(folder)
            app.buttons["Create"].tap()
            app.buttons["Save"].tap()
            app.buttons["collectionPicker"].press(forDuration: 0.6)
            XCTAssertTrue(app.buttons[folder].waitForExistence(timeout: 5))
            app.buttons[folder].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.press(forDuration: 0.6)
            XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Clipping"].exists)
            let shareProof = XCTAttachment(screenshot: app.screenshot())
            shareProof.name = "Long press opens the share sheet"
            shareProof.lifetime = .keepAlways
            add(shareProof)
            app.buttons["Close"].firstMatch.tap()
            app.buttons["Settings"].press(forDuration: 0.6)
            app.buttons["Notifications"].tap()
            XCTAssertTrue(app.buttons["Enable Notifications"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Enable Notifications"].isHittable)
            app.buttons["Done"].tap()
            row.swipeLeft()
            app.buttons["Delete"].tap()
            XCTAssertFalse(row.exists)
            app.buttons["History"].tap()
            XCTAssertTrue(app.navigationBars["History"].exists)
        }

        @MainActor
        func testImagePreviewAndOriginalFileIntent() async throws {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", "dark"]
            app.launch()
            allowPasteIfPresented()
            let definitions = IntentDefinitions(bundleIdentifier: "de.thamo.clipity")
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 250))
            let data = renderer.pngData { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 250))
                ("Image preview" as NSString).draw(
                    at: CGPoint(x: 30, y: 90),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.white])
            }
            let title = "Thumbnail proof \(UUID().uuidString.prefix(6))"
            _ = try await definitions.intents["AddClippingFileIntent"].makeIntent(
                file: IntentFile(data: data, filename: "Preview.png", type: .png), title: title, keep: false
            ).run()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.images["Image preview"].firstMatch.waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Glass navigation and image preview"
            attachment.lifetime = .keepAlways
            add(attachment)

            let file = IntentFile(data: Data("File intent preservation".utf8), filename: "Notes.txt", type: .plainText)
            let added = try await definitions.intents["AddClippingFileIntent"].makeIntent(file: file, keep: false).run()
            let entity: AnyAppEntity = try added.value
            let returned = try await definitions.intents["GetClippingFileIntent"].makeIntent(clipping: entity).run()
            let result: IntentFile = try returned.value
            XCTAssertEqual(result.data, file.data)
            XCTAssertEqual(result.filename, file.filename)
        }
    }
#endif
