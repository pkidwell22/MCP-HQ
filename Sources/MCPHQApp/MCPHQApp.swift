import SwiftUI
import MCPHQCore

@main
struct MCPHQApp: App {
    var body: some Scene {
        WindowGroup("MCP-HQ") {
            DashboardView()
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState
    @Published private(set) var lastRefreshedText: String = "Not refreshed yet"

    private let sourceProvider: DefaultConfigSourceProvider
    private let stateBuilder: DashboardStateBuilder
    private let processScanner: MCPProcessScanner

    init(
        sourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        stateBuilder: DashboardStateBuilder = DashboardStateBuilder(),
        processScanner: MCPProcessScanner = MCPProcessScanner()
    ) {
        self.sourceProvider = sourceProvider
        self.stateBuilder = stateBuilder
        self.processScanner = processScanner
        self.state = stateBuilder.build(from: ScanResult(servers: [], sources: [], issues: []))
    }

    func refresh() {
        let scanner = ConfigScanner(configSources: sourceProvider.sources())
        let configResult = scanner.scan()
        let processes = processScanner.scan()
        state = stateBuilder.build(from: ScanResult(
            servers: configResult.servers,
            sources: configResult.sources,
            issues: configResult.issues + ServerDiagnosticChecker().issues(servers: configResult.servers, sources: configResult.sources),
            processes: processes,
            processMatches: ServerProcessMatcher().matches(servers: configResult.servers, processes: processes)
        ))
        lastRefreshedText = Self.relativeRefreshText(date: Date())
    }

    private static func relativeRefreshText(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Last refreshed at \(formatter.string(from: date))"
    }
}

struct DashboardView: View {
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("MCP-HQ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .task {
            model.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MCP-HQ")
                    .font(.largeTitle.bold())
                Text("Native control center for local MCP servers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            SummaryGrid(summary: model.state.summary)

            if !model.state.issueRows.isEmpty {
                IssueList(issueRows: model.state.issueRows)
            }

            Spacer()

            Text(model.lastRefreshedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 280)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inventory")
                        .font(.title2.bold())
                    Text(model.state.summary.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    model.refresh()
                }
            }
            .padding([.horizontal, .top])

            if model.state.serverRows.isEmpty, model.state.processRows.isEmpty {
                EmptyInventoryView()
            } else {
                List {
                    if !model.state.serverRows.isEmpty {
                        Section("Configured servers") {
                            ForEach(model.state.serverRows) { row in
                                ServerRowView(row: row)
                                    .padding(.vertical, 6)
                            }
                        }
                    }

                    if !model.state.processRows.isEmpty {
                        Section("Running MCP-like processes") {
                            ForEach(model.state.processRows) { row in
                                ProcessRowView(row: row)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct SummaryGrid: View {
    let summary: DashboardSummary

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                SummaryCard(title: "Servers", value: "\(summary.serverCount)")
                SummaryCard(title: "Processes", value: "\(summary.processCount)")
            }
            GridRow {
                SummaryCard(title: "Sources", value: "\(summary.sourceCount)")
                SummaryCard(title: "Warnings", value: "\(summary.warningCount)")
            }
            GridRow {
                SummaryCard(title: "Errors", value: "\(summary.errorCount)")
            }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct IssueList: View {
    let issueRows: [DashboardIssueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues")
                .font(.headline)
            ForEach(issueRows) { issue in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(issue.severityLabel.uppercased()) • \(issue.agentName)")
                        .font(.caption.bold())
                    Text(issue.message)
                        .font(.caption)
                    Text(issue.sourcePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(issue.severityLabel == "error" ? Color.red.opacity(0.12) : Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct ServerRowView: View {
    let row: DashboardServerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(.headline)
                Text(row.transport.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(row.envSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.connectionSummary)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)

            Text(row.processSummary)
                .font(.caption)
                .foregroundStyle(row.processSummary.hasPrefix("Matched") ? .green : .secondary)

            Text(row.sourcePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if !row.redactedEnvBindings.isEmpty {
                DisclosureGroup("Environment") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(row.redactedEnvBindings.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(row.redactedEnvBindings[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }
}

struct ProcessRowView: View {
    let row: DashboardProcessRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.executableName)
                    .font(.headline)
                Text("pid \(row.pid)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(row.matchReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.commandLine)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

struct EmptyInventoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No MCP servers found yet")
                .font(.title3.bold())
            Text("MCP-HQ scans known macOS config paths for Claude, Gemini, Hermes, Cursor, Windsurf, Continue, and Goose. Add an MCP server in one of those apps, then refresh.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
