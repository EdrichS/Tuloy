import Foundation

/// Runs a program and collects its output, giving up after `timeout` seconds.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var errors: String
    }

    static func run(_ program: URL, arguments: [String], environment: [String: String]? = nil,
                    directory: URL? = nil, timeout: TimeInterval) async throws -> Result {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let output = outputPipe.fileHandleForReading
        let errors = errorPipe.fileHandleForReading

        let (exits, exited) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exited.finish() }
        try process.run()
        let pid = process.processIdentifier

        // Read while it runs, so a chatty program can't fill the pipe and stall.
        let readOutput = Task.detached { output.readDataToEndOfFile() }
        let readErrors = Task.detached { errors.readDataToEndOfFile() }

        // Ask it to stop at the deadline, and insist a few seconds later.
        let watchdog = Task.detached {
            guard (try? await Task.sleep(for: .seconds(timeout))) != nil else { return false }
            kill(pid, SIGTERM)
            if (try? await Task.sleep(for: .seconds(3))) != nil { kill(pid, SIGKILL) }
            return true
        }

        for await _ in exits {}
        watchdog.cancel()
        if await watchdog.value { throw PingError.timedOut }

        return Result(
            status: process.terminationStatus,
            output: String(decoding: await readOutput.value, as: UTF8.self),
            errors: String(decoding: await readErrors.value, as: UTF8.self)
        )
    }
}
