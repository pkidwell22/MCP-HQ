import XCTest
@testable import MCPHQCore

final class StatusMenuSnapshotTests: XCTestCase {
    func testSnapshotSummarizesHealthyInventoryForMenuBar() {
        let state = DashboardState(
            summary: DashboardSummary(
                serverCount: 6,
                processCount: 12,
                sourceCount: 2,
                issueCount: 0,
                warningCount: 0,
                errorCount: 0,
                statusText: "6 servers • 12 processes • 2 sources"
            ),
            serverRows: [],
            processRows: [],
            issueRows: []
        )

        let snapshot = StatusMenuSnapshot(state: state, isProbing: false)

        XCTAssertEqual(snapshot.title, "MCP-HQ")
        XCTAssertEqual(snapshot.summaryText, "6 servers • 12 processes")
        XCTAssertEqual(snapshot.detailText, "2 sources • No issues")
        XCTAssertEqual(snapshot.systemImage, "network")
        XCTAssertTrue(snapshot.canRunProbes)
    }

    func testSnapshotPrioritizesErrorsAndDisablesProbeWhileProbing() {
        let state = DashboardState(
            summary: DashboardSummary(
                serverCount: 2,
                processCount: 1,
                sourceCount: 1,
                issueCount: 3,
                warningCount: 2,
                errorCount: 1,
                statusText: "2 servers • 1 process • 1 source • 1 error • 2 warnings"
            ),
            serverRows: [],
            processRows: [],
            issueRows: []
        )

        let snapshot = StatusMenuSnapshot(state: state, isProbing: true)

        XCTAssertEqual(snapshot.summaryText, "2 servers • 1 process")
        XCTAssertEqual(snapshot.detailText, "1 source • 1 error • 2 warnings")
        XCTAssertEqual(snapshot.systemImage, "exclamationmark.octagon.fill")
        XCTAssertFalse(snapshot.canRunProbes)
    }

    func testSnapshotShowsProbingStatus() {
        let state = DashboardState(
            summary: DashboardSummary(
                serverCount: 1,
                processCount: 0,
                sourceCount: 1,
                issueCount: 1,
                warningCount: 1,
                errorCount: 0,
                statusText: "1 server • 0 processes • 1 source • 1 warning"
            ),
            serverRows: [],
            processRows: [],
            issueRows: []
        )

        let snapshot = StatusMenuSnapshot(state: state, isProbing: true)

        XCTAssertEqual(snapshot.probeActionTitle, "Probing…")
        XCTAssertEqual(snapshot.systemImage, "exclamationmark.triangle.fill")
    }
}
