import Foundation
import Testing
@testable import Tuloy

@Suite struct ShellTests {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func collectsOutputErrorsAndExitCode() async throws {
        let run = try await Shell.run(sh, arguments: ["-c", "echo hello; echo oops >&2; exit 3"], timeout: 10)
        #expect(run.output == "hello\n")
        #expect(run.errors == "oops\n")
        #expect(run.status == 3)
    }

    @Test func passesTheEnvironmentAndFolder() async throws {
        let run = try await Shell.run(sh, arguments: ["-c", "echo $GREETING; pwd"], environment: ["GREETING": "tuloy"],
                                      directory: URL(fileURLWithPath: "/usr"), timeout: 10)
        #expect(run.output == "tuloy\n/usr\n")
    }

    @Test func handlesMoreOutputThanAPipeHolds() async throws {
        // A pipe holds about 64 KB. A program that prints more would stall if nobody were reading.
        let run = try await Shell.run(sh, arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x"], timeout: 10)
        #expect(run.output.count == 300_000)
    }

    @Test func givesUpAfterTheTimeout() async {
        let started = Date()
        await #expect(throws: PingError.timedOut) {
            try await Shell.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func throwsWhenTheProgramIsMissing() async {
        await #expect(throws: (any Error).self) {
            try await Shell.run(URL(fileURLWithPath: "/nonexistent/claude"), arguments: [], timeout: 5)
        }
    }

    @Test func noLimitMeansNoLimit() async throws {
        let result = try await Shell.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 1; echo done"], timeout: nil)
        #expect(result.output == "done\n")
    }
}
