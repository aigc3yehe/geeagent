import AVFoundation
import XCTest
@testable import GeeAgentMac

final class SpeechTranscriptionServiceTests: XCTestCase {
    func testLocalWhisperDoesNotReuseStaleTranscriptWhenExpectedOutputIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        let staleTranscriptDirectory = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: staleTranscriptDirectory, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        try "stale text".write(
            to: staleTranscriptDirectory.appendingPathComponent("old.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SpeechTranscriptionService(
            runner: SpeechTranscriptionMockRunner(writeExpectedTranscript: false)
        )

        do {
            _ = try await service.transcribeFile(audioURL, providerID: .localWhisper)
            XCTFail("Expected transcription to fail when Whisper did not create the expected transcript file.")
        } catch AudioCaptureError.transcriptionFailed(let message) {
            XCTAssertEqual(message, "Whisper finished but no transcript text was produced.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalWhisperReadsExpectedTranscriptFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SpeechTranscriptionService(
            runner: SpeechTranscriptionMockRunner(writeExpectedTranscript: true)
        )
        let result = try await service.transcribeFile(audioURL, providerID: .localWhisper)

        XCTAssertEqual(result.transcriptText, "fresh text")
        XCTAssertEqual(result.providerID, .localWhisper)
        XCTAssertEqual(result.audioURL, audioURL)
    }

    func testLocalWhisperPrefersFasterWhisperWhenPythonPackageExists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = SpeechTranscriptionMockRunner(
            backend: .fasterWhisper,
            writeExpectedTranscript: true
        )
        let service = SpeechTranscriptionService(runner: runner)
        let result = try await service.transcribeFile(audioURL, providerID: .localWhisper)

        XCTAssertEqual(result.transcriptText, "fresh text")
    }

    func testLocalWhisperSurfacesTimeoutAsUserFacingFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SpeechTranscriptionService(
            runner: SpeechTranscriptionMockRunner(
                backend: .fasterWhisper,
                commandResult: GearCommandResult(
                    exitCode: 124,
                    stdout: "",
                    stderr: "Command timed out after 180s: python3"
                )
            )
        )

        do {
            _ = try await service.transcribeFile(audioURL, providerID: .localWhisper)
            XCTFail("Expected timeout to surface as a transcription failure.")
        } catch AudioCaptureError.transcriptionFailed(let message) {
            XCTAssertEqual(
                message,
                "Local Whisper transcription timed out. Try a shorter recording or a smaller local model."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalSenseVoiceReadsGlobalCommandTranscriptFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SpeechTranscriptionService(
            runner: SpeechTranscriptionMockRunner(
                backend: .senseVoice,
                writeExpectedTranscript: true
            )
        )
        let result = try await service.transcribeFile(audioURL, providerID: .localSenseVoice)

        XCTAssertEqual(result.transcriptText, "fresh text")
        XCTAssertEqual(result.providerID, .localSenseVoice)
        XCTAssertEqual(result.audioURL, audioURL)
    }

    func testLocalSenseVoiceMissingCommandIsProviderUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("sample.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SpeechTranscriptionService(
            runner: SpeechTranscriptionMockRunner(backend: .noBackend)
        )

        do {
            _ = try await service.transcribeFile(audioURL, providerID: .localSenseVoice)
            XCTFail("Expected transcription to fail when SenseVoice is not installed.")
        } catch AudioCaptureError.providerUnavailable(let message) {
            XCTAssertTrue(message.contains("sensevoice-transcribe"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFasterWhisperScriptUsesCachedLocalModelOnly() {
        XCTAssertTrue(SpeechTranscriptionService.fasterWhisperScript.contains("local_files_only=True"))
        XCTAssertTrue(SpeechTranscriptionService.fasterWhisperScript.contains("models--Systran--faster-whisper-base"))
        XCTAssertTrue(SpeechTranscriptionService.fasterWhisperScript.contains("No cached faster-whisper model was found."))
    }

    func testPunctuationOnlyTranscriptIsNotMeaningful() {
        XCTAssertFalse(SpeechTranscriptionService.isMeaningfulTranscript("... ... ..."))
        XCTAssertFalse(SpeechTranscriptionService.isMeaningfulTranscript("... ..."))
        XCTAssertTrue(SpeechTranscriptionService.isMeaningfulTranscript("hello"))
        XCTAssertTrue(SpeechTranscriptionService.isMeaningfulTranscript("audio transcript"))
    }

    func testSilentAudioFailsBeforeTranscription() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-stt-tests-\(UUID().uuidString)", isDirectory: true)
        let audioURL = root.appendingPathComponent("silent.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTestWAV(to: audioURL, amplitude: 0)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try SpeechTranscriptionService.validateAudibleSignal(audioURL)) { error in
            guard case AudioCaptureError.noSpeechDetected = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private func writeTestWAV(to url: URL, amplitude: Float = 0.2) throws {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let frameCount: AVAudioFrameCount = 16_000
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for frame in 0..<Int(frameCount) {
        let phase = Float(frame) / 16_000 * 440 * 2 * Float.pi
        samples[frame] = sin(phase) * amplitude
    }
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
    )
    try file.write(from: buffer)
}

private struct SpeechTranscriptionMockRunner: GearCommandRunning {
    enum Backend {
        case openAIWhisper
        case fasterWhisper
        case senseVoice
        case noBackend
    }

    var backend: Backend = .openAIWhisper
    var writeExpectedTranscript: Bool = false
    var commandResult: GearCommandResult?

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        await run(command, arguments: arguments, timeoutSeconds: nil)
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        if command == "command", arguments == ["-v", "python3"] {
            return backend == .fasterWhisper
                ? GearCommandResult(exitCode: 0, stdout: "/usr/bin/python3\n", stderr: "")
                : GearCommandResult(exitCode: 127, stdout: "", stderr: "")
        }
        if command == "python3",
           arguments.count == 2,
           arguments[0] == "-c",
           arguments[1] == "import faster_whisper" {
            return backend == .fasterWhisper
                ? GearCommandResult(exitCode: 0, stdout: "", stderr: "")
                : GearCommandResult(exitCode: 1, stdout: "", stderr: "No module named faster_whisper")
        }
        if command == "python3" {
            if let commandResult {
                return commandResult
            }
            if writeExpectedTranscript,
               let transcriptPath = arguments.last {
                let transcriptURL = URL(fileURLWithPath: transcriptPath)
                try? FileManager.default.createDirectory(
                    at: transcriptURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? "fresh text".write(to: transcriptURL, atomically: true, encoding: .utf8)
            }
            return GearCommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        if command == "command", arguments == ["-v", "whisper"] {
            return backend == .openAIWhisper
                ? GearCommandResult(exitCode: 0, stdout: "/usr/local/bin/whisper\n", stderr: "")
                : GearCommandResult(exitCode: 127, stdout: "", stderr: "")
        }
        if command == "command", arguments == ["-v", "sensevoice-transcribe"] {
            return backend == .senseVoice
                ? GearCommandResult(exitCode: 0, stdout: "/Users/example/.local/bin/sensevoice-transcribe\n", stderr: "")
                : GearCommandResult(exitCode: 127, stdout: "", stderr: "")
        }
        if command == "/Users/example/.local/bin/sensevoice-transcribe" {
            if writeExpectedTranscript,
               let outputIndex = arguments.firstIndex(of: "--output"),
               arguments.indices.contains(outputIndex + 1) {
                let transcriptURL = URL(fileURLWithPath: arguments[outputIndex + 1])
                try? FileManager.default.createDirectory(
                    at: transcriptURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? "fresh text".write(to: transcriptURL, atomically: true, encoding: .utf8)
            }
            return commandResult ?? GearCommandResult(
                exitCode: 0,
                stdout: #"{"text":"fresh text","fallback_attempted":false}"#,
                stderr: ""
            )
        }
        if command == "whisper" {
            if writeExpectedTranscript,
               let audioPath = arguments.first,
               let outputIndex = arguments.firstIndex(of: "--output_dir"),
               arguments.indices.contains(outputIndex + 1) {
                let audioURL = URL(fileURLWithPath: audioPath)
                let outputDirectory = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
                let transcriptURL = outputDirectory
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension("txt")
                try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try? "fresh text".write(to: transcriptURL, atomically: true, encoding: .utf8)
            }
            return GearCommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return GearCommandResult(exitCode: 127, stdout: "", stderr: "unexpected command")
    }
}
