import Foundation

// ClaudeService — headless Claude Code CLI transport (macOS only).
//
// Wraps `claude -p --output-format json` per the ticket-03 research:
// - subscription auth via the user's Keychain (no API key)
// - explicit binary lookup (GUI apps don't get /opt/homebrew/bin on PATH)
// - prompt fed via stdin (avoids ARG_MAX / quoting issues)
// - `--permission-mode dontAsk --allowedTools Read` so calls never prompt
// - `--max-turns` >= 8 because tool turns count against the cap
// - `--resume <session_id>` threads follow-ups (sessions are cwd-scoped)
//
// On iPadOS the service reports `.unavailableOnPlatform` and every call
// throws `ClaudeError.unavailable` — callers degrade gracefully.

enum ClaudeAvailability: Equatable, Sendable {
    case available(binary: URL)
    case binaryNotFound
    case unavailableOnPlatform
}

enum ClaudeError: LocalizedError {
    case unavailable(ClaudeAvailability)
    case notLoggedIn
    case maxTurnsExceeded
    case malformedResponse(String)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable(.binaryNotFound):
            return "The Claude CLI was not found. Install Claude Code (brew install --cask claude-code) or set its path in Settings."
        case .unavailable(.unavailableOnPlatform):
            return "Claude features need the Mac app for now."
        case .unavailable:
            return "Claude is unavailable."
        case .notLoggedIn:
            return "Claude Code is not logged in. Run `claude` once in Terminal and sign in."
        case .maxTurnsExceeded:
            return "Claude ran out of turns before finishing."
        case .malformedResponse(let detail):
            return "Unexpected response from Claude: \(detail)"
        case .processFailed(let code, let stderr):
            return "Claude exited with code \(code). \(stderr.prefix(300))"
        case .timedOut:
            return "Claude took too long and was stopped."
        }
    }
}

/// One decoded reply from a `claude -p` invocation.
struct ClaudeReply: Sendable {
    let text: String
    let sessionID: String?
    /// Raw JSON of the `structured_output` field when `jsonSchema` was passed.
    let structuredOutput: Data?
    let costUSD: Double?
    let durationMs: Int?

    func decodeStructured<T: Decodable>(_ type: T.Type) throws -> T {
        guard let structuredOutput else {
            throw ClaudeError.malformedResponse("missing structured_output")
        }
        return try JSONDecoder().decode(type, from: structuredOutput)
    }
}

/// Parameters for one headless call. Defaults follow the research recommendation.
struct ClaudeRequest: Sendable {
    var prompt: String
    var systemPrompt: String?
    /// Working directory — set to the book's wiki directory so relative `Read`s
    /// hit wiki files and session storage is scoped per book.
    var workingDirectory: URL?
    var allowedTools: [String] = ["Read"]
    var maxTurns: Int = 12
    var model: String? = "sonnet"
    var resumeSessionID: String?
    /// JSON schema string; when set the reply carries `structuredOutput`.
    var jsonSchema: String?
    var timeout: TimeInterval = 300

    init(prompt: String) { self.prompt = prompt }
}

final class ClaudeService: Sendable {
    static let shared = ClaudeService()

    /// UserDefaults override for the binary path (escape hatch for exotic installs).
    static let binaryPathDefaultsKey = "ClaudeBinaryPath"

    private static let binaryCandidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.local/bin/claude",
        NSHomeDirectory() + "/.claude/local/claude",
    ]

    /// Global cap: wiki generation runs 1-at-a-time through its own queue and
    /// interactive calls slot into the second lane, so neither starves the other.
    private let gate = AsyncGate(capacity: 2)

    // MARK: Availability

    var availability: ClaudeAvailability {
        #if os(macOS)
        if let override = UserDefaults.standard.string(forKey: Self.binaryPathDefaultsKey),
           FileManager.default.isExecutableFile(atPath: override) {
            return .available(binary: URL(fileURLWithPath: override))
        }
        for path in Self.binaryCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return .available(binary: URL(fileURLWithPath: path))
        }
        return .binaryNotFound
        #else
        return .unavailableOnPlatform
        #endif
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    // MARK: Core call

    func run(_ request: ClaudeRequest) async throws -> ClaudeReply {
        #if os(macOS)
        guard case .available(let binary) = availability else {
            throw ClaudeError.unavailable(availability)
        }
        await gate.acquire()
        defer { Task { await gate.release() } }
        return try await Self.spawn(binary: binary, request: request)
        #else
        throw ClaudeError.unavailable(.unavailableOnPlatform)
        #endif
    }

    /// Convenience for ticket 08 &co: ask a question against an assembled
    /// context (see ContextAssembler). Pass `resume` for thread follow-ups.
    func ask(
        _ question: String,
        context: AssembledContext,
        resume sessionID: String? = nil,
        jsonSchema: String? = nil,
        model: String? = "sonnet",
        maxTurns: Int = 12
    ) async throws -> ClaudeReply {
        var request = ClaudeRequest(prompt: context.prompt(question: question, isFollowUp: sessionID != nil))
        request.systemPrompt = context.systemPrompt
        request.workingDirectory = context.workingDirectory
        request.resumeSessionID = sessionID
        request.jsonSchema = jsonSchema
        request.model = model
        request.maxTurns = maxTurns
        return try await run(request)
    }

    #if os(macOS)
    private static func spawn(binary: URL, request: ClaudeRequest) async throws -> ClaudeReply {
        var args = ["-p", "--output-format", "json", "--permission-mode", "dontAsk"]
        args += ["--allowedTools", request.allowedTools.joined(separator: ",")]
        args += ["--max-turns", String(request.maxTurns)]
        if let model = request.model { args += ["--model", model] }
        if let system = request.systemPrompt { args += ["--append-system-prompt", system] }
        if let resume = request.resumeSessionID { args += ["--resume", resume] }
        if let schema = request.jsonSchema { args += ["--json-schema", schema] }

        let process = Process()
        process.executableURL = binary
        process.arguments = args
        if let cwd = request.workingDirectory {
            try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
            process.currentDirectoryURL = cwd
        }

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Feed the prompt via stdin off the calling task, then close to signal EOF.
        let promptData = Data(request.prompt.utf8)
        DispatchQueue.global(qos: .utility).async {
            try? stdin.fileHandleForWriting.write(contentsOf: promptData)
            try? stdin.fileHandleForWriting.close()
        }

        // Drain pipes concurrently to avoid buffer deadlock on large outputs.
        async let outData: Data = Self.drain(stdout)
        async let errData: Data = Self.drain(stderr)

        // Watchdog.
        let timeout = request.timeout
        let watchdog = Task.detached {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning { process.terminate() }
        }

        await Self.waitForExit(process)
        watchdog.cancel()

        let out = await outData
        let err = await errData

        if process.terminationReason == .uncaughtSignal {
            throw ClaudeError.timedOut
        }
        let errText = String(data: err, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 || !out.isEmpty else {
            if errText.localizedCaseInsensitiveContains("not logged in") {
                throw ClaudeError.notLoggedIn
            }
            throw ClaudeError.processFailed(exitCode: process.terminationStatus, stderr: errText)
        }
        return try decode(out, stderr: errText)
    }

    private static func drain(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            if !process.isRunning { process.terminationHandler = nil; continuation.resume() }
        }
    }

    private static func decode(_ data: Data, stderr: String) throws -> ClaudeReply {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            if snippet.localizedCaseInsensitiveContains("not logged in")
                || stderr.localizedCaseInsensitiveContains("not logged in") {
                throw ClaudeError.notLoggedIn
            }
            throw ClaudeError.malformedResponse(snippet)
        }
        let subtype = object["subtype"] as? String
        if subtype == "error_max_turns" { throw ClaudeError.maxTurnsExceeded }
        let text = object["result"] as? String
        if (object["is_error"] as? Bool) == true {
            let message = text ?? "is_error with no result"
            if message.localizedCaseInsensitiveContains("not logged in") {
                throw ClaudeError.notLoggedIn
            }
            throw ClaudeError.malformedResponse(message)
        }
        guard let text else { throw ClaudeError.malformedResponse("missing result field (subtype: \(subtype ?? "nil"))") }
        var structured: Data?
        if let structuredObject = object["structured_output"],
           JSONSerialization.isValidJSONObject(structuredObject) {
            structured = try? JSONSerialization.data(withJSONObject: structuredObject)
        }
        return ClaudeReply(
            text: text,
            sessionID: object["session_id"] as? String,
            structuredOutput: structured,
            costUSD: object["total_cost_usd"] as? Double,
            durationMs: object["duration_ms"] as? Int
        )
    }
    #endif
}

/// Minimal async counting semaphore (FIFO-ish, sufficient for a 2-lane cap).
actor AsyncGate {
    private let capacity: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int) { self.capacity = capacity }

    func acquire() async {
        if inUse < capacity { inUse += 1; return }
        // Suspend; the releasing task hands its slot to us directly.
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            inUse -= 1
        } else {
            waiters.removeFirst().resume() // slot handed off, inUse unchanged
        }
    }
}
