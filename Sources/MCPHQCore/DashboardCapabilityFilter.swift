import Foundation

public struct DashboardCapabilityFilter: Equatable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isActive: Bool {
        !query.isEmpty
    }

    public func filteredToolNames(_ names: [String]) -> [String] {
        filter(names) { [$0] }
    }

    public func filteredTools(_ tools: [MCPToolDetail]) -> [MCPToolDetail] {
        filter(tools) { tool in
            [tool.name, tool.description, tool.inputSchemaSummary]
        }
    }

    public func filteredResourceNames(_ names: [String]) -> [String] {
        filter(names) { [$0] }
    }

    public func filteredResources(_ resources: [MCPResourceDetail]) -> [MCPResourceDetail] {
        filter(resources) { resource in
            [resource.name, resource.uri, resource.description, resource.mimeType]
        }
    }

    public func filteredPromptNames(_ names: [String]) -> [String] {
        filter(names) { [$0] }
    }

    public func filteredPrompts(_ prompts: [MCPPromptDetail]) -> [MCPPromptDetail] {
        filter(prompts) { prompt in
            [prompt.name, prompt.description, prompt.argumentSummary]
        }
    }

    private func filter<Element>(_ elements: [Element], searchableValues: (Element) -> [String]) -> [Element] {
        guard isActive else { return elements }
        let terms = normalizedTerms
        guard !terms.isEmpty else { return elements }
        return elements.filter { element in
            let haystack = searchableValues(element)
                .map(Self.normalized)
                .joined(separator: "\n")
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private var normalizedTerms: [String] {
        Self.normalized(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
