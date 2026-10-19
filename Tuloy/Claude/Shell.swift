import Foundation

/// Runs a program and collects its output, giving up after `timeout` seconds.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var errors: String
    }

    /// `input` is written to the program's standard input, then closed. Cancelling the task that
    /// called this stops the program.
    static func run(_ program: URL, arguments: [String], environment: [String: String]? = nil,
                    directory: URL? = nil, input: Data? = nil, timeout: TimeInterval) async throws -> Result {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory

        let inputPipe = input.map { _ in Pipe() }
        process.standardInput = inputPipe ?? FileHandle.nullDevice

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

        if let inputPipe, let input {
            // Written off to the side, so a long message can't fill the pipe and stall this task.
            let writer = inputPipe.fileHandleForWriting
            // If the program quits without reading it all, writing must fail quietly, not end Tuloy.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            Task.detached {
                try? writer.write(contentsOf: input)
                try? writer.close()
            }
        }

        // Read while it runs, so a chatty program can't fill the pipe and stall.
        let readOutput = Task.detached { output.readDataToEndOfFile() }
        let readErrors = Task.detached { errors.readDataToEndOfFile() }

        // Ask it to stop at the deadline, and insist a few seconds later. The deadline counts only time
        // the Mac is awake: a ping caught by sleep isn't "too slow", and gets its full time on waking.
        let watchdog = Task.detached {
            guard (try? await Task.sleep(for: .seconds(timeout), tolerance: nil, clock: SuspendingClock())) != nil else { return false }
            kill(pid, SIGTERM)
            if (try? await Task.sleep(for: .seconds(3))) != nil { kill(pid, SIGKILL) }
            return true
        }

        await withTaskCancellationHandler {
            for await _ in exits {}
        } onCancel: {
            // Stopped by you (a message's Stop button): end it the same polite way.
            kill(pid, SIGTERM)
        }
        watchdog.cancel()
        if await watchdog.value { throw PingError.timedOut }
        if Task.isCancelled { throw CancellationError() }

        return Result(
            status: process.terminationStatus,
            output: String(decoding: await readOutput.value, as: UTF8.self),
            errors: String(decoding: await readErrors.value, as: UTF8.self)
        )
    }
}
