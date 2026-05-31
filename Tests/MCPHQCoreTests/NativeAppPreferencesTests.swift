import XCTest
@testable import MCPHQCore

final class NativeAppPreferencesTests: XCTestCase {
    func testHistoryLimitUsesSafeBounds() {
        XCTAssertEqual(NativeAppPreferences.sanitizedHistoryLimit(-5), NativeAppPreferences.minimumHistoryLimit)
        XCTAssertEqual(NativeAppPreferences.sanitizedHistoryLimit(0), NativeAppPreferences.minimumHistoryLimit)
        XCTAssertEqual(NativeAppPreferences.sanitizedHistoryLimit(25), 25)
        XCTAssertEqual(NativeAppPreferences.sanitizedHistoryLimit(500), NativeAppPreferences.maximumHistoryLimit)
    }

    func testPreferredExportFormatFallsBackToText() {
        XCTAssertEqual(NativeAppPreferences.preferredExportFormat(rawValue: "json"), .json)
        XCTAssertEqual(NativeAppPreferences.preferredExportFormat(rawValue: "text"), .text)
        XCTAssertEqual(NativeAppPreferences.preferredExportFormat(rawValue: ""), .text)
        XCTAssertEqual(NativeAppPreferences.preferredExportFormat(rawValue: "xml"), .text)
    }

    func testWindowFrameAutosaveNameDefaultsAndTrims() {
        XCTAssertEqual(
            NativeAppPreferences.sanitizedWindowFrameAutosaveName(nil),
            NativeAppPreferences.dashboardWindowFrameAutosaveName
        )
        XCTAssertEqual(
            NativeAppPreferences.sanitizedWindowFrameAutosaveName("   \n"),
            NativeAppPreferences.dashboardWindowFrameAutosaveName
        )
        XCTAssertEqual(
            NativeAppPreferences.sanitizedWindowFrameAutosaveName("  custom.dashboard.window  "),
            "custom.dashboard.window"
        )
    }

    func testEndpointPathDefaultsExpandsTildeAndStandardizes() {
        let home = URL(fileURLWithPath: "/Users/tester")

        XCTAssertEqual(
            NativeAppPreferences.sanitizedEndpointFilePath("   ", homeDirectory: home),
            NativeAppPreferences.defaultControlEndpointFilePath(homeDirectory: home)
        )
        XCTAssertEqual(
            NativeAppPreferences.sanitizedEndpointFilePath("~/Library/Application Support/MCP-HQ/custom-endpoint.json", homeDirectory: home),
            "/Users/tester/Library/Application Support/MCP-HQ/custom-endpoint.json"
        )
        XCTAssertEqual(
            NativeAppPreferences.sanitizedEndpointFilePath("/tmp/../tmp/mcphq-endpoint.json", homeDirectory: home),
            "/tmp/mcphq-endpoint.json"
        )
    }
}
