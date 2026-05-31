import XCTest
@testable import MCPHQCore

final class DashboardCapabilityFilterTests: XCTestCase {
    func testInactiveFilterReturnsOriginalCapabilityLists() {
        let filter = DashboardCapabilityFilter(query: "   ")
        let names = ["create_issue", "search_repositories"]
        let tools = [MCPToolDetail(name: "create_issue")]

        XCTAssertEqual(filter.filteredToolNames(names), names)
        XCTAssertEqual(filter.filteredTools(tools), tools)
    }

    func testFiltersToolsByNameDescriptionAndSchemaTerms() {
        let filter = DashboardCapabilityFilter(query: "issue repo")
        let tools = [
            MCPToolDetail(
                name: "create_issue",
                description: "Create an issue in a repository",
                inputSchemaSummary: "object; required: title; props: owner, repo"
            ),
            MCPToolDetail(
                name: "list_branches",
                description: "List branches",
                inputSchemaSummary: "object; props: owner"
            ),
        ]

        XCTAssertEqual(filter.filteredTools(tools).map(\.name), ["create_issue"])
    }

    func testFiltersResourcesByUriNameDescriptionAndMimeType() {
        let filter = DashboardCapabilityFilter(query: "readme markdown")
        let resources = [
            MCPResourceDetail(uri: "file:///repo/README.md", name: "Repo docs", description: "Project readme", mimeType: "text/markdown"),
            MCPResourceDetail(uri: "file:///repo/package.json", name: "Package", description: "Manifest", mimeType: "application/json"),
        ]

        XCTAssertEqual(filter.filteredResources(resources).map(\.uri), ["file:///repo/README.md"])
    }

    func testFiltersPromptsByNameDescriptionAndArgumentSummary() {
        let filter = DashboardCapabilityFilter(query: "draft title")
        let prompts = [
            MCPPromptDetail(name: "draft_issue", description: "Draft an issue", argumentSummary: "required: title"),
            MCPPromptDetail(name: "summarize", description: "Summarize content", argumentSummary: "optional: length"),
        ]

        XCTAssertEqual(filter.filteredPrompts(prompts).map(\.name), ["draft_issue"])
    }

    func testFilteringUsesAlreadyRedactedCapabilityText() {
        let tool = MCPToolDetail(
            name: "danger-ghp_secretToken1234567890",
            description: "leaky token=ghp_secretToken1234567890",
            inputSchemaSummary: "api_key=sk-secretValue1234567890"
        )

        XCTAssertEqual(tool.name, "danger-<redacted>")
        XCTAssertEqual(tool.description, "leaky token=<redacted>")
        XCTAssertEqual(tool.inputSchemaSummary, "api_key=<redacted>")
        XCTAssertEqual(DashboardCapabilityFilter(query: "ghp_secretToken1234567890").filteredTools([tool]), [])
        XCTAssertEqual(DashboardCapabilityFilter(query: "redacted").filteredTools([tool]), [tool])
    }
}
