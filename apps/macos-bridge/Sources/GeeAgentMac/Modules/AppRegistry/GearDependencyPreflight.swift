import Foundation

protocol GearCommandRunning: Sendable {
    func run(_ command: String, arguments: [String]) async -> GearCommandResult
    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult
}

extension GearCommandRunning {
    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        await run(command, arguments: arguments)
    }
}

struct GearCommandResult: Hashable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct GearShellCommandRunner: GearCommandRunning, Sendable {
    func run(_ command: String, arguments: [String] = []) async -> GearCommandResult {
        await run(command, arguments: arguments, timeoutSeconds: nil)
    }

    func run(_ command: String, arguments: [String] = [], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", Self.shellCommand(command, arguments: arguments)]
            process.environment = Self.processEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = GearCommandOutputBuffer()
            let stderrBuffer = GearCommandOutputBuffer()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            let processBox = GearRunningProcessBox(process: process)
            let timeoutTask = timeoutSeconds.map { timeoutSeconds in
                Task.detached(priority: .utility) {
                    let nanoseconds = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else {
                        return
                    }
                    processBox.terminateForTimeout()
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                timeoutTask?.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                return GearCommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
            }

            timeoutTask?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

            var stderr = stderrBuffer.string()
            if processBox.didTimeOut {
                let timeoutMessage = "Command timed out after \(Int(timeoutSeconds ?? 0))s: \(command)"
                stderr = [stderr, timeoutMessage].filter { !$0.isEmpty }.joined(separator: "\n")
                return GearCommandResult(exitCode: 124, stdout: stdoutBuffer.string(), stderr: stderr)
            }

            return GearCommandResult(exitCode: process.terminationStatus, stdout: stdoutBuffer.string(), stderr: stderr)
        }.value
    }

    private static func shellCommand(_ command: String, arguments: [String]) -> String {
        ([command] + arguments)
            .map(shellQuote)
            .joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HYPERFRAMES_NO_UPDATE_CHECK"] = "1"
        environment["CI"] = environment["CI"] ?? "1"

        let commonPaths = [
            environment["PATH"],
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = commonPaths.compactMap(\.self).joined(separator: ":")
        return environment
    }
}

private final class GearCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

private final class GearRunningProcessBox: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.lock()
        let value = timedOut
        lock.unlock()
        return value
    }

    func terminateForTimeout() {
        guard process.isRunning else {
            return
        }

        lock.lock()
        timedOut = true
        lock.unlock()

        process.terminate()
        Thread.sleep(forTimeInterval: 1)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

struct GearDependencyPreflight: Sendable {
    private static let detectionTimeoutSeconds: TimeInterval = 20

    var runner: GearCommandRunning

    func check(plan: GearDependencyPlan?, rootURL: URL) async -> [GearDependencyCheckResult] {
        guard let plan else {
            return []
        }

        var results: [GearDependencyCheckResult] = []
        for item in plan.items where item.required {
            results.append(await check(item: item, rootURL: rootURL))
        }
        return results
    }

    func check(item: GearDependencyItem, rootURL: URL) async -> GearDependencyCheckResult {
        switch item.scope {
        case .global:
            return await checkGlobal(item)
        case .gearLocal:
            return checkGearLocal(item, rootURL: rootURL)
        }
    }

    private func checkGlobal(_ item: GearDependencyItem) async -> GearDependencyCheckResult {
        guard let detect = item.detect, let command = detect.command, !command.isEmpty else {
            return GearDependencyCheckResult(
                item: item,
                isSatisfied: false,
                summary: "No global detection command declared for \(item.id).",
                detail: nil
            )
        }

        let pathResult = await runner.run(
            "command",
            arguments: ["-v", command],
            timeoutSeconds: Self.detectionTimeoutSeconds
        )
        guard pathResult.exitCode == 0 else {
            return GearDependencyCheckResult(
                item: item,
                isSatisfied: false,
                summary: "`\(command)` is not installed.",
                detail: pathResult.combinedOutput
            )
        }

        let commandResult = await runner.run(
            command,
            arguments: detect.args ?? [],
            timeoutSeconds: Self.detectionTimeoutSeconds
        )
        guard commandResult.exitCode == 0 else {
            return GearDependencyCheckResult(
                item: item,
                isSatisfied: false,
                summary: "`\(command)` did not pass its health check.",
                detail: commandResult.combinedOutput
            )
        }

        if let minVersion = detect.minVersion,
           let detected = Self.firstVersion(in: commandResult.combinedOutput),
           Self.compareVersions(detected, minVersion) == .orderedAscending
        {
            return GearDependencyCheckResult(
                item: item,
                isSatisfied: false,
                summary: "`\(command)` is \(detected), requires \(minVersion)+.",
                detail: commandResult.combinedOutput
            )
        }

        if let healthCommand = detect.healthCommand {
            let health = await runner.run(
                healthCommand,
                arguments: detect.healthArgs ?? [],
                timeoutSeconds: Self.detectionTimeoutSeconds
            )
            guard health.exitCode == 0 else {
                return GearDependencyCheckResult(
                    item: item,
                    isSatisfied: false,
                    summary: "`\(healthCommand)` health check failed.",
                    detail: health.combinedOutput
                )
            }
        }

        return GearDependencyCheckResult(
            item: item,
            isSatisfied: true,
            summary: "`\(command)` is available.",
            detail: commandResult.combinedOutput
        )
    }

    private func checkGearLocal(_ item: GearDependencyItem, rootURL: URL) -> GearDependencyCheckResult {
        guard let target = item.target, !target.isEmpty else {
            return GearDependencyCheckResult(
                item: item,
                isSatisfied: false,
                summary: "No local target declared for \(item.id).",
                detail: nil
            )
        }

        let targetURL = rootURL.appendingPathComponent(target)
        let exists = FileManager.default.fileExists(atPath: targetURL.path)
        return GearDependencyCheckResult(
            item: item,
            isSatisfied: exists,
            summary: exists ? "`\(target)` is present." : "`\(target)` is missing.",
            detail: targetURL.path
        )
    }

    static func firstVersion(in text: String) -> String? {
        let pattern = #"\d+(?:\.\d+){0,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let versionRange = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[versionRange])
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}
