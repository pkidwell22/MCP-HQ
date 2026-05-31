import Foundation
import MCPHQCore

func controlServeResult(args: [String]) -> MCPHQCommandResult? {
    var port: UInt16 = 0
    var token: String?
    var requiresToken = true
    var endpointFileURL: URL?
    var index = 0

    while index < args.count {
        let argument = args[index]
        switch argument {
        case "--port":
            guard index + 1 < args.count, let parsedPort = UInt16(args[index + 1]) else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid value for --port")
            }
            port = parsedPort
            index += 2
        case "--token":
            guard index + 1 < args.count else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --token")
            }
            token = args[index + 1]
            requiresToken = true
            index += 2
        case "--no-token":
            requiresToken = false
            token = nil
            index += 1
        case "--endpoint-file":
            guard index + 1 < args.count else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file")
            }
            endpointFileURL = URL(fileURLWithPath: args[index + 1])
            index += 2
        default:
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown control serve option: \(argument)")
        }
    }

    do {
        let endpointStore = endpointFileURL.map { LocalControlEndpointStore(fileURL: $0) } ?? .defaultStore()
        let runtime = try LocalControlServerLauncher(endpointStore: endpointStore).start(
            port: port,
            token: token,
            requiresToken: requiresToken
        )
        let endpoint = runtime.endpoint
        print("MCP-HQ local control server")
        print("URL: \(endpoint.controlURL.absoluteString)")
        print("Endpoint file: \(endpointStore.fileURL.path)")
        print("Auth: \(endpoint.token == nil ? "disabled" : "token saved to endpoint file")")
        fflush(stdout)

        let semaphore = DispatchSemaphore(value: 0)
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let signalQueue = DispatchQueue(label: "com.mcphq.control-server.signals")
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        interruptSource.setEventHandler {
            runtime.stop()
            semaphore.signal()
        }
        terminateSource.setEventHandler {
            runtime.stop()
            semaphore.signal()
        }
        interruptSource.resume()
        terminateSource.resume()
        semaphore.wait()
        return MCPHQCommandResult(exitCode: 0, stdout: "", stderr: "")
    } catch {
        return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Control serve failed: \(error)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "control", args.dropFirst().first == "serve" {
    let result = controlServeResult(args: Array(args.dropFirst(2))) ?? MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Control serve failed")
    if !result.stdout.isEmpty {
        print(result.stdout)
    }
    if !result.stderr.isEmpty {
        fputs(result.stderr + "\n", stderr)
    }
    Foundation.exit(result.exitCode)
}

let result: MCPHQCommandResult

do {
    result = try MCPHQCommand().run(args: args)
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
