import Foundation
import Darwin

enum RuntimeProcessError: LocalizedError {
    case runtimeUnavailable(String)
    case runtimeInvocation(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message),
             let .runtimeInvocation(message),
             let .unsupported(message):
            return message
        }
    }
}

struct RuntimeCommandLaunch {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
    let fingerprintURL: URL
    let environment: [String: String]?
}

private struct RuntimeServerResponseDTO: Decodable {
    let id: String
    let ok: Bool
    let output: String?
    let error: String?
}

final class RuntimeCommandServer {
    private let label: String
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let serverLock = NSLock()
    private var serverProcess: Process?
    private var serverStdin: FileHandle?
    private var serverStdout: FileHandle?
    private var serverStderr: FileHandle?
    private var serverStderrBuffer: ProcessPipeCollector?
    private var launchKey: String?
    private var launchFingerprintDate: Date?

    init(label: String) {
        self.label = label
    }

    deinit {
        stop()
    }

    func stop() {
        serverLock.lock()
        defer { serverLock.unlock() }
        stopLocked()
    }

    func run(
        command: String,
        args: [String],
        launch: RuntimeCommandLaunch,
        timeout: TimeInterval
    ) throws -> Data {
        serverLock.lock()
        defer { serverLock.unlock() }

        try ensureServerLocked(launch: launch)

        guard let stdin = serverStdin, let stdout = serverStdout else {
            throw RuntimeProcessError.runtimeUnavailable(
                "The \(label) server is not connected."
            )
        }

        let requestID = UUID().uuidString
        let requestObject: [String: Any] = [
            "id": requestID,
            "command": command,
            "args": args,
        ]
        let requestData = try JSONSerialization.data(
            withJSONObject: requestObject,
            options: [.sortedKeys]
        )
        guard var requestLine = String(data: requestData, encoding: .utf8) else {
            throw RuntimeProcessError.runtimeInvocation(
                "failed to encode \(label) server request"
            )
        }
        requestLine.append("\n")
        try stdin.write(contentsOf: Data(requestLine.utf8))

        let responseData = try readServerLine(from: stdout, timeout: timeout)
        let response: RuntimeServerResponseDTO
        do {
            response = try decoder.decode(RuntimeServerResponseDTO.self, from: responseData)
        } catch {
            let raw = String(data: responseData, encoding: .utf8) ?? "<non-utf8 output>"
            throw RuntimeProcessError.runtimeInvocation(
                "The \(label) server returned invalid JSON: \(raw)"
            )
        }

        guard response.id == requestID else {
            throw RuntimeProcessError.runtimeInvocation(
                "The \(label) server returned a mismatched response."
            )
        }
        guard response.ok else {
            throw RuntimeProcessError.runtimeInvocation(
                response.error ?? "The \(label) server failed this request."
            )
        }
        guard let output = response.output else {
            throw RuntimeProcessError.runtimeInvocation(
                "The \(label) server returned no output."
            )
        }
        return Data(output.utf8)
    }

    private func ensureServerLocked(launch: RuntimeCommandLaunch) throws {
        let nextKey = launchKey(for: launch)
        let nextFingerprintDate = Self.modificationDate(for: launch.fingerprintURL)
        if let process = serverProcess,
           process.isRunning,
           launchKey == nextKey,
           launchFingerprintDate == nextFingerprintDate {
            return
        }

        stopLocked()

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectoryURL
        process.environment = launch.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stderrBuffer = ProcessPipeCollector()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw RuntimeProcessError.runtimeUnavailable(
                "Failed to launch the \(label) server: \(error.localizedDescription)"
            )
        }

        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        serverProcess = process
        serverStdin = stdinPipe.fileHandleForWriting
        serverStdout = stdoutPipe.fileHandleForReading
        serverStderr = stderrPipe.fileHandleForReading
        serverStderrBuffer = stderrBuffer
        launchKey = nextKey
        launchFingerprintDate = nextFingerprintDate
    }

    private func readServerLine(from stdout: FileHandle, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ServerLineReadResult()

        DispatchQueue.global(qos: .userInitiated).async {
            let readResult: Result<Data, RuntimeProcessError>
            do {
                readResult = .success(try Self.readServerLineBlocking(from: stdout))
            } catch let error as RuntimeProcessError {
                readResult = .failure(error)
            } catch {
                readResult = .failure(.runtimeInvocation(error.localizedDescription))
            }

            resultBox.store(readResult)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            let stderr = serverStderrSummaryLocked()
            stopLocked()
            let stderrDetail = stderr.map { " Stderr: \($0)" } ?? ""
            throw RuntimeProcessError.runtimeInvocation(
                "The \(label) server did not reply within \(Int(timeout)) seconds. GeeAgent restarted it so Quick Input would not stay loading forever.\(stderrDetail)"
            )
        }

        switch resultBox.snapshot() {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        case .none:
            throw RuntimeProcessError.runtimeInvocation(
                "The \(label) server finished without a response."
            )
        }
    }

    private static func readServerLineBlocking(from stdout: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk: Data
            do {
                chunk = try stdout.read(upToCount: 1) ?? Data()
            } catch {
                throw RuntimeProcessError.runtimeInvocation(
                    "The runtime command server output could not be read: \(error.localizedDescription)"
                )
            }
            if chunk.isEmpty {
                throw RuntimeProcessError.runtimeInvocation(
                    "The runtime command server exited before replying."
                )
            }
            if let newlineIndex = chunk.firstIndex(of: 0x0A) {
                buffer.append(chunk[..<newlineIndex])
                return buffer
            }
            buffer.append(chunk)
        }
    }

    private func stopLocked() {
        serverStderr?.readabilityHandler = nil
        serverStdin?.closeFile()
        serverStdout?.closeFile()
        serverStderr?.closeFile()
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil
        serverStdin = nil
        serverStdout = nil
        serverStderr = nil
        serverStderrBuffer = nil
        launchKey = nil
        launchFingerprintDate = nil
    }

    private static func modificationDate(for url: URL) -> Date? {
        var fileStatus = stat()
        let result = url.withUnsafeFileSystemRepresentation { pathPointer -> Int32 in
            guard let pathPointer else { return -1 }
            return lstat(pathPointer, &fileStatus)
        }
        guard result == 0 else { return nil }

        let seconds = TimeInterval(fileStatus.st_mtimespec.tv_sec)
        let nanoseconds = TimeInterval(fileStatus.st_mtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanoseconds)
    }

    private func launchKey(for launch: RuntimeCommandLaunch) -> String {
        ([launch.executableURL.path] + launch.arguments + [launch.currentDirectoryURL?.path ?? ""])
            .joined(separator: "\u{1F}")
    }

    private func serverStderrSummaryLocked() -> String? {
        guard let stderrData = serverStderrBuffer?.snapshot(),
              let raw = String(data: stderrData, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.suffix(800))
    }
}

final class ProcessPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ nextData: Data) {
        lock.lock()
        data = nextData
        lock.unlock()
    }

    func append(_ nextData: Data) {
        guard !nextData.isEmpty else { return }
        lock.lock()
        data.append(nextData)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class ServerLineReadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, RuntimeProcessError>?

    func store(_ nextResult: Result<Data, RuntimeProcessError>) {
        lock.lock()
        result = nextResult
        lock.unlock()
    }

    func snapshot() -> Result<Data, RuntimeProcessError>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
