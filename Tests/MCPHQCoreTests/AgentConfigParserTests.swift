import XCTest
@testable import MCPHQCore

final class AgentConfigParserTests: XCTestCase {
    func testParsesCodexTOMLMCPServersWithEnvAndHeaders() throws {
        let source = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let data = """
        [mcp_servers.node_repl]
        command = "/Applications/Codex.app/Contents/Resources/node_repl"
        args = ["--token", "${NODE_REPL_TOKEN}"]

        [mcp_servers.node_repl.env]
        NODE_ENV = "production"

        [mcp_servers.node_repl.headers]
        Authorization = "Bearer ${NODE_REPL_TOKEN}"

        [mcp_servers.remote_docs]
        server_url = "https://example.test/mcp"
        transport = "streamable_http"
        """.data(using: .utf8)!

        let servers = try AgentConfigParser().parse(data: data, source: source)

        XCTAssertEqual(servers.map(\.displayName), ["node_repl", "remote_docs"])
        XCTAssertEqual(servers[0].id, ServerDefinition.canonicalID(agent: .codex, sourcePath: source.path, name: "node_repl"))
        XCTAssertEqual(servers[0].transport, .stdio)
        XCTAssertEqual(servers[0].command, "/Applications/Codex.app/Contents/Resources/node_repl")
        XCTAssertEqual(servers[0].args, ["--token", "${NODE_REPL_TOKEN}"])
        XCTAssertEqual(servers[0].envBindings["NODE_ENV"], "production")
        XCTAssertEqual(servers[0].headers["Authorization"], "Bearer ${NODE_REPL_TOKEN}")
        XCTAssertEqual(servers[1].transport, .streamableHTTP)
        XCTAssertEqual(servers[1].url, "https://example.test/mcp")
    }

    func testParsesOpenCodeLocalAndRemoteMCPServers() throws {
        let source = ConfigSource(agent: .opencode, path: "/tmp/opencode.json")
        let data = """
        {
          "mcp": {
            "local": {
              "type": "local",
              "command": ["bunx", "@modelcontextprotocol/server-filesystem", "/tmp"],
              "environment": { "API_TOKEN": "${API_TOKEN}" }
            },
            "remote": {
              "type": "remote",
              "url": "https://example.test/mcp",
              "headers": { "Authorization": "Bearer ${API_TOKEN}" }
            }
          }
        }
        """.data(using: .utf8)!

        let servers = try AgentConfigParser().parse(data: data, source: source)

        XCTAssertEqual(servers.map(\.displayName), ["local", "remote"])
        XCTAssertEqual(servers[0].transport, .stdio)
        XCTAssertEqual(servers[0].command, "bunx")
        XCTAssertEqual(servers[0].args, ["@modelcontextprotocol/server-filesystem", "/tmp"])
        XCTAssertEqual(servers[0].envBindings["API_TOKEN"], "${API_TOKEN}")
        XCTAssertEqual(servers[1].transport, .streamableHTTP)
        XCTAssertEqual(servers[1].url, "https://example.test/mcp")
        XCTAssertEqual(servers[1].headers["Authorization"], "Bearer ${API_TOKEN}")
    }

    func testParsesJSONStyleCodingAgentConfigs() throws {
        let data = """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"],
              "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
            },
            "remote": {
              "serverUrl": "https://example.test/mcp",
              "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" }
            },
            "disabled": {
              "command": "ignored",
              "disabled": true
            }
          }
        }
        """.data(using: .utf8)!

        for agent in [AgentID.antigravity, .pi, .cursor, .windsurf, .continue] {
            let source = ConfigSource(agent: agent, path: "/tmp/\(agent.rawValue).json")
            let servers = try AgentConfigParser().parse(data: data, source: source)

            XCTAssertEqual(servers.map(\.displayName), ["github", "remote"])
            XCTAssertEqual(servers[0].id, ServerDefinition.canonicalID(agent: agent, sourcePath: source.path, name: "github"))
            XCTAssertEqual(servers[0].transport, .stdio)
            XCTAssertEqual(servers[0].command, "npx")
            XCTAssertEqual(servers[0].args, ["-y", "@modelcontextprotocol/server-github"])
            XCTAssertEqual(servers[0].envBindings["GITHUB_TOKEN"], "${GITHUB_TOKEN}")
            XCTAssertEqual(servers[1].transport, .streamableHTTP)
            XCTAssertEqual(servers[1].headers["Authorization"], "Bearer ${GITHUB_TOKEN}")
        }
    }

    func testParsesGooseYAMLServers() throws {
        let source = ConfigSource(agent: .goose, path: "/tmp/goose.yaml")
        let data = """
        mcp_servers:
          github:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-github"
            env:
              GITHUB_TOKEN: ${GITHUB_TOKEN}
          remote:
            url: https://example.test/mcp
            transport: sse
            headers:
              Authorization: Bearer ${GITHUB_TOKEN}
        """.data(using: .utf8)!

        let servers = try AgentConfigParser().parse(data: data, source: source)

        XCTAssertEqual(servers.map(\.displayName), ["github", "remote"])
        XCTAssertEqual(servers[0].transport, .stdio)
        XCTAssertEqual(servers[0].args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(servers[0].envBindings["GITHUB_TOKEN"], "${GITHUB_TOKEN}")
        XCTAssertEqual(servers[1].transport, .sse)
        XCTAssertEqual(servers[1].url, "https://example.test/mcp")
        XCTAssertEqual(servers[1].headers["Authorization"], "Bearer ${GITHUB_TOKEN}")
    }
}
