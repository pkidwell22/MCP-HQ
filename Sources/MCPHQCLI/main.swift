import Foundation
import MCPHQCore

let result: MCPHQCommandResult

do {
    result = try MCPHQCommand().run(args: Array(CommandLine.arguments.dropFirst()))
} catch {
    result = MCPHQCommandResult(
        exitCode: 1,
        stdout: "",
        stderr: "Unexpected error: \(error)"
    )
}

if !result.stdout.isEmpty {
    print(result.stdout)
}

if !result.stderr.isEmpty {
    fputs(result.stderr + "\n", stderr)
}

Foundation.exit(result.exitCode)
