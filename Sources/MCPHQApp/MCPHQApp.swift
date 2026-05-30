import SwiftUI
import MCPHQCore
#if os(macOS)
import AppKit
#endif

@main
struct MCPHQApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        Window("MCP-HQ", id: "dashboard") {
            DashboardView(model: model)
                .frame(minWidth: 840, minHeight: 560)
        }

        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            Label(model.statusMenuSnapshot.title, systemImage: model.statusMenuSnapshot.systemImage)
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState
    @Published private(set) var lastRefreshedText: String = "Not refreshed yet"
    @Published private(set) var isProbing: Bool = false

    private let sourceProvider: DefaultConfigSourceProvider
    private let stateBuilder: DashboardStateBuilder
    private let scanCoordinator: ScanCoordinator

    var statusMenuSnapshot: StatusMenuSnapshot {
        StatusMenuSnapshot(state: state, isProbing: isProbing)
    }

    init(
        sourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        stateBuilder: DashboardStateBuilder = DashboardStateBuilder(),
        scanCoordinator: ScanCoordinator = ScanCoordinator()
    ) {
        self.sourceProvider = sourceProvider
        self.stateBuilder = stateBuilder
        self.scanCoordinator = scanCoordinator
        self.state = stateBuilder.build(from: ScanResult(servers: [], sources: [], issues: []))
        refresh()
    }

    func refresh() {
        let result = scanCoordinator.scan(sources: sourceProvider.sources(), includeProbes: false)
        state = stateBuilder.build(from: result)
        lastRefreshedText = Self.relativeRefreshText(date: Date())
    }

    func runProbes() {
        guard !isProbing else { return }
        isProbing = true
        let sources = sourceProvider.sources()
        let scanCoordinator = scanCoordinator
        let stateBuilder = stateBuilder
        Task.detached(priority: .userInitiated) {
            let result = scanCoordinator.scan(sources: sources, includeProbes: true)
            let nextState = stateBuilder.build(from: result)
            await MainActor.run {
                self.state = nextState
                self.lastRefreshedText = Self.relativeRefreshText(date: Date())
                self.isProbing = false
            }
        }
    }

    private static func relativeRefreshText(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Last refreshed at \(formatter.string(from: date))"
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var selectedServerID: String?

    private var selectedServerDetail: DashboardServerDetail? {
        if let selectedServerID,
           let detail = model.state.serverDetails.first(where: { $0.id == selectedServerID }) {
            return detail
        }
        return model.state.serverDetails.first
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("MCP-HQ")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(model.isProbing ? "Probing…" : "Run Probes") {
                    model.runProbes()
                }
                .disabled(model.isProbing)

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
                Button(model.isProbing ? "Probing…" : "Run Probes") {
                    model.runProbes()
                }
                .disabled(model.isProbing)
                Button("Refresh") {
                    model.refresh()
                }
            }
            .padding([.horizontal, .top])

            if let selectedServerDetail {
                ServerInspectorView(detail: selectedServerDetail)
                    .padding(.horizontal)
            }

            if model.state.serverRows.isEmpty, model.state.processRows.isEmpty {
                EmptyInventoryView()
            } else {
                List {
                    if !model.state.serverRows.isEmpty {
                        Section("Configured servers") {
                            ForEach(model.state.serverRows) { row in
                                Button {
                                    selectedServerID = row.id
                                } label: {
                                    ServerRowView(row: row)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(selectedServerID == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
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

struct StatusMenuView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    private var snapshot: StatusMenuSnapshot { model.statusMenuSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.summaryText)
                .font(.headline)
            Text(snapshot.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Dashboard") {
                openWindow(id: "dashboard")
                #if os(macOS)
                NSApp.activate(ignoringOtherApps: true)
                #endif
            }

            Button("Refresh") {
                model.refresh()
            }

            Button(snapshot.probeActionTitle) {
                model.runProbes()
            }
            .disabled(!snapshot.canRunProbes)

            Divider()

            Button("Quit MCP-HQ") {
                #if os(macOS)
                NSApp.terminate(nil)
                #endif
            }
            .keyboardShortcut("q", modifiers: [.command])
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

struct ServerInspectorView: View {
    let detail: DashboardServerDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inspector")
                    .font(.headline)
                Text(detail.displayName)
                    .font(.subheadline.bold())
                Text(detail.transport.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(detail.toolSummary)
                    .font(.caption.bold())
                    .foregroundStyle(detail.toolSummary.hasPrefix("Healthy") ? .green : .secondary)
            }

            Text(detail.connectionSummary)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Label(detail.processSummary, systemImage: "cpu")
                Label(detail.envSummary, systemImage: "key")
                Label(detail.sourcePath, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !detail.issueRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detail.issueRows) { issue in
                        Text("\(issue.severityLabel.uppercased()): \(issue.message)")
                            .font(.caption)
                            .foregroundStyle(issue.severityLabel == "error" ? .red : .yellow)
                    }
                }
            }

            if !detail.toolNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tools")
                        .font(.caption.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(detail.toolNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial, in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if !detail.toolDetails.isEmpty {
                DisclosureGroup("Tool details") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(detail.toolDetails) { tool in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.name)
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .textSelection(.enabled)
                                if !tool.description.isEmpty {
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !tool.inputSchemaSummary.isEmpty {
                                    Text("Input: \(tool.inputSchemaSummary)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.resourceNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resources • \(detail.resourceSummary)")
                        .font(.caption.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(detail.resourceNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial, in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if !detail.resourceDetails.isEmpty {
                DisclosureGroup("Resource details") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(detail.resourceDetails) { resource in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(resource.name.isEmpty ? resource.uri : resource.name)
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .textSelection(.enabled)
                                Text(resource.uri)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if !resource.description.isEmpty {
                                    Text(resource.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !resource.mimeType.isEmpty {
                                    Text(resource.mimeType)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.promptNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompts • \(detail.promptSummary)")
                        .font(.caption.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(detail.promptNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial, in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if !detail.promptDetails.isEmpty {
                DisclosureGroup("Prompt details") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(detail.promptDetails) { prompt in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(prompt.name)
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .textSelection(.enabled)
                                if !prompt.description.isEmpty {
                                    Text(prompt.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !prompt.argumentSummary.isEmpty {
                                    Text("Arguments: \(prompt.argumentSummary)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.redactedEnvBindings.isEmpty {
                DisclosureGroup("Environment") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.redactedEnvBindings.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(detail.redactedEnvBindings[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.processRows.isEmpty {
                DisclosureGroup("Matched processes") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.processRows) { process in
                            Text("pid \(process.pid) • \(process.commandLine)")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
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

            Text(row.toolSummary)
                .font(.caption)
                .foregroundStyle(row.toolSummary.hasPrefix("Healthy") ? .green : .secondary)

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
