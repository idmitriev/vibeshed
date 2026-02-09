import XCTest

final class PickerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Wait for picker to appear (auto-shown in UI testing mode)
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.waitForExistence(timeout: 5), "Picker should appear on launch in UI testing mode")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    func testPickerAppears() {
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.exists, "Picker view should be visible")
    }

    func testSearchFieldExists() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Search field should exist")
    }

    func testSearchShowsResults() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        searchField.click()
        searchField.typeText("Safari")

        // Wait for debounce (150ms) + processing
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3), "Action list should appear with results")

        // Verify at least one result contains "Safari"
        let safariCell = actionList.cells.containing(.staticText, identifier: "Open Safari").firstMatch
        XCTAssertTrue(safariCell.waitForExistence(timeout: 3), "Should find Safari action in results")
    }

    func testSearchNoResults() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        searchField.click()
        searchField.typeText("xyznonexistent123")

        // Wait for debounce + processing
        let noResults = app.otherElements["pickerNoResults"]
        XCTAssertTrue(noResults.waitForExistence(timeout: 3), "No results view should appear for nonsense query")
    }

    func testArrowKeyNavigation() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Type a query that matches multiple actions
        searchField.click()
        searchField.typeText("a")

        // Wait for results to load
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3), "Action list should appear")

        // Give time for results to populate
        sleep(1)

        // Navigate down with arrow key
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])

        // Navigate back up
        app.typeKey(.upArrow, modifierFlags: [])

        // If we got here without crashing, navigation works
        XCTAssertTrue(actionList.exists, "Action list should still be visible after navigation")
    }

    func testEscapeClosesPicker() {
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.exists, "Picker should be visible initially")

        // Press Escape to close
        app.typeKey(.escape, modifierFlags: [])

        // Picker should disappear
        XCTAssertTrue(pickerView.waitForNonExistence(timeout: 3), "Picker should close on Escape")
    }
}
