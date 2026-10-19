import Foundation

/// Reads what Claude Code printed after one of your scheduled messages (`--output-format stream-json`).
enum MessageOutput {

    static func read(_ output: String, status: Int32 = 0, errors: String = "", now: Date = Date()) -> MessageOutcome {
        let events = StreamEvent.lines(in: output)
        let result = events.last { $0.type == "result" }
        let start = events.first { $0.type == "system" }

        var outcome = MessageOutcome(result: .failure(.failed("Claude Code didn't answer.")))
        outcome.report = PingOutput.limits(in: events, now: now)
        outcome.sessionID = result?.sessionID ?? start?.sessionID
        outcome.model = start?.model
        outcome.version = PingOutput.version(in: output)
        outcome.usedAPIKey = PingOutput.usesAPIKey(in: output)
        outcome.refused = (result?.permissionDenials ?? []).compactMap(\.tool_name)

        if let result, result.isError != true, status == 0 {
            outcome.result = .success(result.result ?? "")
        } else {
            let message = result?.result ?? result?.errors?.first ?? errors
            outcome.result = .failure(PingError(message: message.isEmpty ? "Claude Code exited with code \(status)." : message))
        }
        return outcome
    }
}
