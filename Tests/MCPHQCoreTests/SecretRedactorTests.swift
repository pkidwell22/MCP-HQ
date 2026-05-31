import XCTest
@testable import MCPHQCore

final class SecretRedactorTests: XCTestCase {
    func testConfigRedactionPreservesEnvReferencesAndSyntax() {
        let text = """
        [mcp_servers.github.env]
        GITHUB_PERSONAL_ACCESS_TOKEN = "${GITHUB_PERSONAL_ACCESS_TOKEN}"
        Authorization = "Bearer ${AUTHORIZATION}"
        """

        let redacted = SecretRedactor.redactConfigText(text)

        XCTAssertTrue(redacted.contains(#"GITHUB_PERSONAL_ACCESS_TOKEN = "${GITHUB_PERSONAL_ACCESS_TOKEN}""#))
        XCTAssertTrue(redacted.contains(#"Authorization = "Bearer ${AUTHORIZATION}""#))
        XCTAssertFalse(redacted.contains("GITHUB_PERSONAL_ACCESS_TOKEN = <redacted>"))
        XCTAssertFalse(redacted.contains("Authorization = <redacted>"))
    }

    func testConfigRedactionRedactsLiteralValuesWithoutBreakingQuotes() {
        let text = """
        {
          "GITHUB_TOKEN" : "ghp_1234567890abcdef",
          "Authorization" : "Bearer ghp_1234567890abcdef"
        }
        GITHUB_TOKEN = "plain-secret-value"
        api_key: plain-secret-value
        """

        let redacted = SecretRedactor.redactConfigText(text)

        XCTAssertTrue(redacted.contains(#""GITHUB_TOKEN" : "<redacted>""#))
        XCTAssertTrue(redacted.contains(#""Authorization" : "Bearer <redacted>""#))
        XCTAssertTrue(redacted.contains(#"GITHUB_TOKEN = "<redacted>""#))
        XCTAssertTrue(redacted.contains(#"api_key: "<redacted>""#))
        XCTAssertFalse(redacted.contains("ghp_1234567890abcdef"))
        XCTAssertFalse(redacted.contains("plain-secret-value"))
    }

    func testConfigRedactionPreservesDiffPrefixes() {
        let text = #"+GITHUB_TOKEN = "${GITHUB_TOKEN}""#

        XCTAssertEqual(
            SecretRedactor.redactConfigText(text),
            #"+GITHUB_TOKEN = "${GITHUB_TOKEN}""#
        )
    }
}
