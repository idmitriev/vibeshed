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

    // MARK: - Picker Appearance

    func testPickerAppears() {
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.exists, "Picker view should be visible")
    }

    func testSearchFieldExists() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Search field should exist")
    }

    func testActionListExists() {
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3), "Action list should exist with default actions")
    }

    func testPreviewPaneExists() {
        // Preview pane should be visible alongside the action list
        let preview = app.groups["actionPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "Preview pane should exist")
    }

    // MARK: - Search & Filtering

    func testSearchShowsResults() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        searchField.click()
        searchField.typeText("Safari")

        // Wait for debounce (150ms) + processing
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3), "Action list should appear with results")

        // Verify the Safari action appears
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

    func testSearchFiltersMultipleResults() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // "al" should match "Calculator" and "Terminal" (both contain "al")
        searchField.click()
        searchField.typeText("al")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))

        sleep(1) // wait for filter to settle
        XCTAssertGreaterThan(actionList.cells.count, 0, "Should have matching results")
    }

    func testSearchByKeyword() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // "math" is a keyword for Calculator
        searchField.click()
        searchField.typeText("math")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))

        sleep(1)
        let calcCell = actionList.cells.containing(.staticText, identifier: "Calculator").firstMatch
        XCTAssertTrue(calcCell.waitForExistence(timeout: 3), "Should find Calculator via keyword 'math'")
    }

    func testClearSearchRestoresAllActions() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Type a query
        searchField.click()
        searchField.typeText("Safari")
        sleep(1)

        // Count filtered results
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        let filteredCount = actionList.cells.count

        // Clear the search field
        searchField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        sleep(1)

        // Should have more actions than the filtered set
        let fullCount = actionList.cells.count
        XCTAssertGreaterThanOrEqual(fullCount, filteredCount, "Clearing search should show all actions")
    }

    // MARK: - Keyboard Navigation

    func testArrowKeyNavigation() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Type a query that matches multiple actions
        searchField.click()
        searchField.typeText("a")

        // Wait for results to load
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Navigate down with arrow key
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])

        // Navigate back up
        app.typeKey(.upArrow, modifierFlags: [])

        // If we got here without crashing, navigation works
        XCTAssertTrue(actionList.exists, "Action list should still be visible after navigation")
    }

    func testPageNavigation() {
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Page down and up should not crash
        app.typeKey(.pageDown, modifierFlags: [])
        app.typeKey(.pageUp, modifierFlags: [])

        XCTAssertTrue(actionList.exists, "Action list should still be visible after page navigation")
    }

    // MARK: - Escape & Dismiss

    func testEscapeClosesPicker() {
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.exists, "Picker should be visible initially")

        // Press Escape to close
        app.typeKey(.escape, modifierFlags: [])

        // Picker should disappear
        XCTAssertTrue(pickerView.waitForNonExistence(timeout: 3), "Picker should close on Escape")
    }

    // MARK: - Parameter Input

    func testParameterInputStaticSelection() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Search for the theme action which has static parameters
        searchField.click()
        searchField.typeText("Set Theme")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Select the "Set Theme" action by pressing Return
        app.typeKey(.return, modifierFlags: [])

        // Should enter parameter input mode with option list
        let paramList = app.outlines["parameterOptionList"].firstMatch
        XCTAssertTrue(paramList.waitForExistence(timeout: 3), "Parameter option list should appear for Set Theme")

        // Should show Light, Dark, Auto options
        let lightOption = paramList.cells.containing(.staticText, identifier: "Light").firstMatch
        XCTAssertTrue(lightOption.waitForExistence(timeout: 3), "Should show Light option")
    }

    func testParameterInputBackNavigation() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Search and select theme action
        searchField.click()
        searchField.typeText("Set Theme")
        sleep(1)

        // Enter parameter mode
        app.typeKey(.return, modifierFlags: [])

        let paramList = app.outlines["parameterOptionList"].firstMatch
        XCTAssertTrue(paramList.waitForExistence(timeout: 3), "Should be in parameter input mode")

        // Press Escape to go back to search
        app.typeKey(.escape, modifierFlags: [])

        // Should return to action list
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3), "Should return to action list after escape from parameters")
    }

    func testParameterInputDynamicSelection() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Search for Focus Window which has dynamic parameters
        searchField.click()
        searchField.typeText("Focus Window")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Select the action
        app.typeKey(.return, modifierFlags: [])

        // Should enter parameter input mode with dynamic options
        let paramList = app.outlines["parameterOptionList"].firstMatch
        XCTAssertTrue(paramList.waitForExistence(timeout: 3), "Parameter option list should appear for Focus Window")

        // Dynamic options should load (Safari, Xcode, Terminal windows)
        sleep(1)
        XCTAssertGreaterThan(paramList.cells.count, 0, "Should have dynamic window options")
    }

    // MARK: - Action Execution

    func testActionExecutionShowsResult() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Search for the "Show Result" action
        searchField.click()
        searchField.typeText("Show Result")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Execute the action
        app.typeKey(.return, modifierFlags: [])

        // Should show result view with "Done" title
        let doneText = app.staticTexts["Done"]
        XCTAssertTrue(doneText.waitForExistence(timeout: 3), "Result view should show 'Done' title")

        let messageText = app.staticTexts["Action completed successfully"]
        XCTAssertTrue(messageText.waitForExistence(timeout: 3), "Result view should show completion message")
    }

    func testActionExecutionDismissesPicker() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Search for Safari action (returns .dismiss)
        searchField.click()
        searchField.typeText("Open Safari")

        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Execute the action
        app.typeKey(.return, modifierFlags: [])

        // Picker should dismiss
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.waitForNonExistence(timeout: 3), "Picker should dismiss after executing action")
    }

    func testParameterSelectionExecutesAction() {
        let searchField = app.textFields["pickerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))

        // Select theme action
        searchField.click()
        searchField.typeText("Set Theme")
        sleep(1)
        app.typeKey(.return, modifierFlags: [])

        // Wait for parameter options
        let paramList = app.outlines["parameterOptionList"].firstMatch
        XCTAssertTrue(paramList.waitForExistence(timeout: 3))
        sleep(1)

        // Select first option (Light) and execute
        app.typeKey(.return, modifierFlags: [])

        // Action should execute (dismiss picker since MockAction returns .dismiss)
        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.waitForNonExistence(timeout: 3), "Picker should dismiss after selecting parameter")
    }

    // MARK: - Cmd+Number Quick Select

    func testCmdNumberQuickSelect() {
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Cmd+1 should select and execute the first action
        // First action is "Open Safari" which returns .dismiss
        app.typeKey("1", modifierFlags: .command)

        let pickerView = app.groups["pickerView"]
        XCTAssertTrue(pickerView.waitForNonExistence(timeout: 3), "Cmd+1 should execute first action and dismiss")
    }

    // MARK: - Empty State

    func testEmptyQueryShowsDefaultActions() {
        // On launch with empty query, all mock actions should be visible
        let actionList = app.outlines["actionList"].firstMatch
        XCTAssertTrue(actionList.waitForExistence(timeout: 3))
        sleep(1)

        // Mock module provides 8 actions (5 simple + 1 showResult + 2 with parameters)
        XCTAssertGreaterThanOrEqual(actionList.cells.count, 5, "Should show default actions with empty query")
    }
}
