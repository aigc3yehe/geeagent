import AVFoundation
import Foundation

actor SpeechTranscriptionService {
    private enum LocalWhisperBackend: Equatable {
        case fasterWhisperPython
        case openAIWhisperCommand
        case whisperCppCommand(String)
    }

    private let runner: GearCommandRunning
    private let fileManager: FileManager
    private let providerSecretStore: ProviderSecretStore
    private let transcriptionTimeoutSeconds: TimeInterval

    init(
        runner: GearCommandRunning = GearShellCommandRunner(),
        fileManager: FileManager = .default,
        providerSecretStore: ProviderSecretStore = ProviderSecretStore(),
        transcriptionTimeoutSeconds: TimeInterval = 180
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.providerSecretStore = providerSecretStore
        self.transcriptionTimeoutSeconds = transcriptionTimeoutSeconds
    }

    func supportsRealtime(providerID: SpeechTranscriptionProviderID) async -> Bool {
        switch providerID {
        case .localWhisper, .localSenseVoice:
            return false
        case .elevenLabs:
            return false
        }
    }

    func transcribeFile(
        _ audioURL: URL,
        providerID: SpeechTranscriptionProviderID
    ) async throws -> SpeechTranscriptionResult {
        switch providerID {
        case .localWhisper:
            return try await transcribeWithLocalWhisper(audioURL)
        case .localSenseVoice:
            return try await transcribeWithLocalSenseVoice(audioURL)
        case .elevenLabs:
            return try await transcribeWithElevenLabs(audioURL)
        }
    }

    private func transcribeWithLocalWhisper(_ audioURL: URL) async throws -> SpeechTranscriptionResult {
        try Self.validateAudibleSignal(audioURL)
        guard let backend = await findLocalWhisperBackend() else {
            throw AudioCaptureError.providerUnavailable(
                "No local Whisper backend was found. Install Python `faster-whisper`, `whisper`, or `whisper-cli`, then try transcription again."
            )
        }

        let outputDirectory = audioURL.deletingLastPathComponent()
            .appendingPathComponent("transcripts", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let transcriptBaseURL = outputDirectory.appendingPathComponent(
            audioURL.deletingPathExtension().lastPathComponent
        )

        let result: GearCommandResult
        switch backend {
        case .fasterWhisperPython:
            result = await runner.run(
                "python3",
                arguments: [
                    "-c",
                    Self.fasterWhisperScript,
                    audioURL.path,
                    transcriptBaseURL.appendingPathExtension("txt").path
                ],
                timeoutSeconds: transcriptionTimeoutSeconds
            )
        case .openAIWhisperCommand:
            result = await runner.run(
                "whisper",
                arguments: [
                    audioURL.path,
                    "--model", "base",
                    "--output_format", "txt",
                    "--output_dir", outputDirectory.path
                ],
                timeoutSeconds: transcriptionTimeoutSeconds
            )
        case let .whisperCppCommand(command):
            guard let modelPath = await findWhisperCppModelPath() else {
                throw AudioCaptureError.providerUnavailable(
                    "Local whisper-cli is installed, but no ggml model file was found. Install a whisper.cpp model such as `ggml-base.bin`, or install Python `faster-whisper`."
                )
            }
            result = await runner.run(
                command,
                arguments: [
                    "-m", modelPath,
                    "-f", audioURL.path,
                    "-otxt",
                    "-of", transcriptBaseURL.path
                ],
                timeoutSeconds: transcriptionTimeoutSeconds
            )
        }

        guard result.exitCode == 0 else {
            throw AudioCaptureError.transcriptionFailed(Self.userFacingFailure(from: result))
        }

        guard let transcriptURL = transcriptURL(preferredBaseURL: transcriptBaseURL),
              let text = try? String(contentsOf: transcriptURL, encoding: .utf8),
              Self.isMeaningfulTranscript(text)
        else {
            throw AudioCaptureError.transcriptionFailed("Whisper finished but no transcript text was produced.")
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpeechTranscriptionResult(
            providerID: .localWhisper,
            transcriptText: trimmedText,
            transcriptURL: transcriptURL,
            audioURL: audioURL,
            durationSeconds: nil,
            status: "ready",
            errorCode: nil,
            errorMessage: nil,
            fallbackAttempted: false
        )
    }

    private func transcribeWithElevenLabs(_ audioURL: URL) async throws -> SpeechTranscriptionResult {
        try Self.validateAudibleSignal(audioURL)
        guard let apiKey = try providerSecretStore.apiKey(
            providerID: "elevenlabs",
            envVar: "ELEVENLABS_API_KEY"
        ), !apiKey.isEmpty else {
            throw AudioCaptureError.providerUnavailable(
                "ElevenLabs API key is not configured. Add it in Settings > Provider Keys, then try transcription again."
            )
        }

        let boundary = "GeeAgentBoundary-\(UUID().uuidString)"
        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else {
            throw AudioCaptureError.providerUnavailable("ElevenLabs speech-to-text endpoint is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        Self.appendMultipartField(name: "model_id", value: "scribe_v1", boundary: boundary, to: &body)
        Self.appendMultipartFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/wav",
            data: try Data(contentsOf: audioURL),
            boundary: boundary,
            to: &body
        )
        body.appendString("--\(boundary)--\r\n")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            throw AudioCaptureError.transcriptionFailed(
                "ElevenLabs transcription request failed: \(error.localizedDescription)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudioCaptureError.transcriptionFailed("ElevenLabs returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data.prefix(600), encoding: .utf8) ?? "No response body."
            throw AudioCaptureError.transcriptionFailed(
                "ElevenLabs transcription failed with HTTP \(httpResponse.statusCode): \(detail)"
            )
        }

        let decoded: ElevenLabsSpeechToTextResponse
        do {
            decoded = try JSONDecoder().decode(ElevenLabsSpeechToTextResponse.self, from: data)
        } catch {
            throw AudioCaptureError.transcriptionFailed(
                "ElevenLabs returned an unreadable transcription response."
            )
        }

        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isMeaningfulTranscript(text) else {
            throw AudioCaptureError.transcriptionFailed("ElevenLabs finished but no transcript text was produced.")
        }

        let transcriptURL = try writeTranscript(
            text,
            audioURL: audioURL,
            suffix: "elevenlabs"
        )
        return SpeechTranscriptionResult(
            providerID: .elevenLabs,
            transcriptText: text,
            transcriptURL: transcriptURL,
            audioURL: audioURL,
            durationSeconds: nil,
            status: "ready",
            errorCode: nil,
            errorMessage: nil,
            fallbackAttempted: false
        )
    }

    private func transcribeWithLocalSenseVoice(_ audioURL: URL) async throws -> SpeechTranscriptionResult {
        try Self.validateAudibleSignal(audioURL)
        guard let command = await findLocalSenseVoiceCommand() else {
            throw AudioCaptureError.providerUnavailable(
                "No local SenseVoice backend was found. Install the global `sensevoice-transcribe` command, then try transcription again."
            )
        }

        let transcriptURL = try transcriptOutputURL(audioURL: audioURL, suffix: "sensevoice")
        let result = await runner.run(
            command,
            arguments: [
                audioURL.path,
                "--format", "json",
                "--output", transcriptURL.path
            ],
            timeoutSeconds: transcriptionTimeoutSeconds
        )

        guard result.exitCode == 0 else {
            throw AudioCaptureError.transcriptionFailed(Self.senseVoiceUserFacingFailure(from: result))
        }

        guard let text = try? String(contentsOf: transcriptURL, encoding: .utf8),
              Self.isMeaningfulTranscript(text)
        else {
            throw AudioCaptureError.transcriptionFailed("SenseVoice finished but no transcript text was produced.")
        }

        return SpeechTranscriptionResult(
            providerID: .localSenseVoice,
            transcriptText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptURL: transcriptURL,
            audioURL: audioURL,
            durationSeconds: nil,
            status: "ready",
            errorCode: nil,
            errorMessage: nil,
            fallbackAttempted: false
        )
    }

    static func validateAudibleSignal(_ audioURL: URL) throws {
        let file = try AVAudioFile(forReading: audioURL)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(min(file.length, 16_000 * 30))
        ) else {
            return
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            return
        }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var peak: Float = 0
        var sumSquares: Float = 0
        var sampleCount = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let value = abs(samples[frame])
                peak = max(peak, value)
                sumSquares += value * value
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else {
            throw AudioCaptureError.noSpeechDetected("No microphone audio was captured. Check the selected macOS input device, then try again.")
        }
        let rms = sqrt(sumSquares / Float(sampleCount))
        guard peak >= 0.001 || rms >= 0.0003 else {
            throw AudioCaptureError.noSpeechDetected("No usable speech was captured. Your current macOS audio input appears silent or extremely quiet.")
        }
    }

    static func isMeaningfulTranscript(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private func findLocalWhisperBackend() async -> LocalWhisperBackend? {
        let python = await runner.run("command", arguments: ["-v", "python3"], timeoutSeconds: 8)
        if python.exitCode == 0 {
            let module = await runner.run(
                "python3",
                arguments: ["-c", "import faster_whisper"],
                timeoutSeconds: 8
            )
            if module.exitCode == 0 {
                return .fasterWhisperPython
            }
        }

        let openAIWhisper = await runner.run("command", arguments: ["-v", "whisper"], timeoutSeconds: 8)
        if openAIWhisper.exitCode == 0 {
            return .openAIWhisperCommand
        }

        let whisperCpp = await runner.run("command", arguments: ["-v", "whisper-cli"], timeoutSeconds: 8)
        if whisperCpp.exitCode == 0 {
            return .whisperCppCommand("whisper-cli")
        }
        return nil
    }

    private func findWhisperCppModelPath() async -> String? {
        for path in Self.whisperCppModelCandidates {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func findLocalSenseVoiceCommand() async -> String? {
        let result = await runner.run("command", arguments: ["-v", "sensevoice-transcribe"], timeoutSeconds: 8)
        guard result.exitCode == 0 else { return nil }
        let command = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? "sensevoice-transcribe" : command
    }

    private func transcriptURL(preferredBaseURL: URL) -> URL? {
        let preferred = preferredBaseURL.appendingPathExtension("txt")
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }
        return nil
    }

    private func writeTranscript(
        _ text: String,
        audioURL: URL,
        suffix: String
    ) throws -> URL {
        let transcriptURL = try transcriptOutputURL(audioURL: audioURL, suffix: suffix)
        try "\(text)\n".write(to: transcriptURL, atomically: true, encoding: .utf8)
        return transcriptURL
    }

    private func transcriptOutputURL(
        audioURL: URL,
        suffix: String
    ) throws -> URL {
        let outputDirectory = audioURL.deletingLastPathComponent()
            .appendingPathComponent("transcripts", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
            .appendingPathComponent("\(audioURL.deletingPathExtension().lastPathComponent)-\(suffix)")
            .appendingPathExtension("txt")
    }

    private struct ElevenLabsSpeechToTextResponse: Decodable {
        var text: String
    }

    private static func appendMultipartField(
        name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    private static func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String,
        to body: inout Data
    ) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
    }

    static let fasterWhisperScript = """
import sys
from pathlib import Path
from faster_whisper import WhisperModel

audio_path = sys.argv[1]
out_path = Path(sys.argv[2])
home = Path.home()
model_candidates = [
    home / ".cache/huggingface/hub/models--Systran--faster-whisper-base/snapshots",
    home / ".cache/huggingface/hub/models--Systran--faster-whisper-tiny.en/snapshots",
    home / ".cache/huggingface/hub/models--Systran--faster-whisper-base.en/snapshots",
]
model_path = None
for snapshots in model_candidates:
    if not snapshots.exists():
        continue
    for candidate in sorted(snapshots.iterdir(), key=lambda item: item.stat().st_mtime, reverse=True):
        if (candidate / "model.bin").exists() and (candidate / "config.json").exists():
            model_path = candidate
            break
    if model_path is not None:
        break
if model_path is None:
    raise SystemExit("No cached faster-whisper model was found. Open the Speech To Text settings to configure an online provider, or pre-download a Systran faster-whisper model.")
model = WhisperModel(str(model_path), device="cpu", compute_type="int8", local_files_only=True)
segments, info = model.transcribe(audio_path, word_timestamps=False, vad_filter=False, beam_size=1)
text = " ".join((segment.text or "").strip() for segment in segments).strip()
if not text:
    raise SystemExit("faster-whisper finished but no transcript text was produced.")
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(text + "\\n", encoding="utf-8")
"""

    private static var whisperCppModelCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Application Support/GeeAgent/Whisper/ggml-base.bin",
            "\(home)/Library/Application Support/GeeAgent/Whisper/ggml-base.en.bin",
            "\(home)/.cache/whisper/ggml-base.bin",
            "\(home)/.cache/whisper/ggml-base.en.bin",
            "/opt/homebrew/share/whisper-cpp/ggml-base.bin",
            "/opt/homebrew/share/whisper-cpp/ggml-base.en.bin",
            "/usr/local/share/whisper-cpp/ggml-base.bin",
            "/usr/local/share/whisper-cpp/ggml-base.en.bin"
        ]
    }

    private static func userFacingFailure(from result: GearCommandResult) -> String {
        let output = result.combinedOutput
        if result.exitCode == 124 || output.localizedCaseInsensitiveContains("command timed out") {
            return "Local Whisper transcription timed out. Try a shorter recording or a smaller local model."
        }
        if output.localizedCaseInsensitiveContains("failed to open 'models/ggml-base.en.bin'")
            || output.localizedCaseInsensitiveContains("failed to open `models/ggml-base.en.bin`")
            || output.localizedCaseInsensitiveContains("loading model from 'models/ggml-base.en.bin'") {
            return "Local whisper-cli could not find its default ggml model. Install a whisper.cpp model or use Python `faster-whisper`."
        }
        if output.localizedCaseInsensitiveContains("failed to read audio file")
            || output.localizedCaseInsensitiveContains("failed to read audio data as wav") {
            return "Local whisper-cli could not read the recorded audio file. GeeAgent records WAV for new sessions; try recording again."
        }
        return output.isEmpty ? "Local Whisper transcription failed." : output
    }

    private static func senseVoiceUserFacingFailure(from result: GearCommandResult) -> String {
        let output = result.combinedOutput
        if result.exitCode == 124 || output.localizedCaseInsensitiveContains("command timed out") {
            return "Local SenseVoice transcription timed out. Try a shorter recording or reduce local CPU load."
        }
        if output.localizedCaseInsensitiveContains("model files were not found") {
            return "Local SenseVoice is installed, but its model files are missing. Reinstall the global SenseVoice model bundle."
        }
        return output.isEmpty ? "Local SenseVoice transcription failed." : output
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
