import Foundation

public enum ConfigSyntaxError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidJSON(line: Int, column: Int, reason: String)
    case invalidYAML(line: Int, reason: String)

    public var description: String {
        switch self {
        case .invalidJSON(let line, let column, let reason):
            return "Invalid JSON at line \(line), column \(column): \(reason)"
        case .invalidYAML(let line, let reason):
            return "Invalid YAML at line \(line): \(reason)"
        }
    }
}

public enum ConfigSyntaxValidator {
    public static func validate(data: Data, agent: AgentID) throws {
        switch agent {
        case .claude, .gemini:
            try validateJSON(data: data)
        case .hermes:
            try validateYAML(data: data)
        case .cursor, .windsurf, .continue, .goose, .unknown:
            return
        }
    }

    private static func validateJSON(data: Data) throws {
        guard !data.isEmpty else { return }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let nsError = error as NSError
            let text = String(data: data, encoding: .utf8) ?? ""
            let index = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int ?? text.count
            let location = lineColumn(in: text, utf16Offset: index)
            let rawReason = (nsError.userInfo["NSDebugDescription"] as? String) ?? nsError.localizedDescription
            throw ConfigSyntaxError.invalidJSON(line: location.line, column: location.column, reason: sanitizedJSONReason(rawReason))
        }
    }

    private static func validateYAML(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            if indentation.contains("\t") {
                throw ConfigSyntaxError.invalidYAML(
                    line: offset + 1,
                    reason: "tabs are not supported for indentation; use spaces."
                )
            }
        }
    }

    private static func sanitizedJSONReason(_ reason: String) -> String {
        let marker = " around line "
        guard let markerRange = reason.range(of: marker, options: .caseInsensitive) else { return reason }
        var prefix = String(reason[..<markerRange.lowerBound])
        if !prefix.hasSuffix(".") { prefix += "." }
        return prefix
    }

    private static func lineColumn(in text: String, utf16Offset: Int) -> (line: Int, column: Int) {
        let clampedOffset = max(0, min(utf16Offset, text.utf16.count))
        var line = 1
        var column = 1
        var currentOffset = 0
        for scalar in text.unicodeScalars {
            if currentOffset >= clampedOffset { break }
            if scalar == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            currentOffset += String(scalar).utf16.count
        }
        return (line, column)
    }
}
