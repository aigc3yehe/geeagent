import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AudioCaptureCoordinator {
    var selectedSource: AudioCaptureSource = .microphone
    var selectedMode: AudioCaptureMode = .transcribe
    var selectedProvider: SpeechTranscriptionProviderID {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: Self.providerPreferenceKey)
        }
    }
    var state: AudioCaptureState = .idle
    var transcriptText: String = ""
    var statusMessage: String = "Ready."
    var lastRecordingURL: URL?
    var lastTranscriptURL: URL?
    var lastArtifact: AudioCaptureArtifact?
    var chatVoiceText: String = ""
    var chatVoiceStatusMessage: String?
    var isChatVoiceInputActive = false

    private let captureService: AudioCaptureService
    private let transcriptionService: SpeechTranscriptionService
    private let userDefaults: UserDefaults
    private var activeSource: AudioCaptureSource = .microphone
    private var activeMode: AudioCaptureMode = .transcribe
    private var activeProvider: SpeechTranscriptionProviderID
    private var activeStartedAt: Date?
    private var activeIsChatInput = false

    private static let providerPreferenceKey = "geeagent.audioCapture.transcriptionProvider"

    init(
        captureService: AudioCaptureService = AudioCaptureService(),
        transcriptionService: SpeechTranscriptionService = SpeechTranscriptionService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.captureService = captureService
        self.transcriptionService = transcriptionService
        self.userDefaults = userDefaults
        let storedProvider = userDefaults.string(forKey: Self.providerPreferenceKey)
        let provider = SpeechTranscriptionProviderID(rawValue: storedProvider ?? "") ?? .localWhisper
        self.selectedProvider = provider
        self.activeProvider = provider
    }

    var isRecording: Bool {
        if case .recording = state {
            return true
        }
        return false
    }

    var canStart: Bool {
        !state.isActive
    }

    var canStop: Bool {
        isRecording
    }

    func startBarSession() {
        startSession(
            source: selectedSource,
            mode: selectedMode,
            provider: selectedProvider,
            isChatInput: false
        )
    }

    func stopBarSession() {
        stopSession(isChatInput: false)
    }

    func startChatVoiceInput() {
        guard !isChatVoiceInputActive else {
            stopChatVoiceInput()
            return
        }
        chatVoiceText = ""
        let started = startSession(
            source: .microphone,
            mode: .transcribe,
            provider: selectedProvider,
            isChatInput: true
        )
        if started {
            chatVoiceStatusMessage = "Listening with \(selectedProvider.title)..."
            isChatVoiceInputActive = true
        }
    }

    func stopChatVoiceInput() {
        guard isChatVoiceInputActive else { return }
        stopSession(isChatInput: true)
    }

    func copyTranscriptToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptText, forType: .string)
        statusMessage = transcriptText.isEmpty ? "No transcript to copy." : "Transcript copied."
    }

    func revealLastRecording() {
        guard let lastRecordingURL else {
            statusMessage = "No saved recording to reveal."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecordingURL])
    }

    @discardableResult
    private func startSession(
        source: AudioCaptureSource,
        mode: AudioCaptureMode,
        provider: SpeechTranscriptionProviderID,
        isChatInput: Bool
    ) -> Bool {
        guard canStart else {
            let message = "Audio capture is already active."
            statusMessage = message
            if isChatInput {
                chatVoiceStatusMessage = message
                isChatVoiceInputActive = false
            }
            return false
        }
        activeSource = source
        activeMode = mode
        activeProvider = provider
        activeStartedAt = nil
        activeIsChatInput = isChatInput
        state = .starting
        if !isChatInput {
            transcriptText = ""
            lastArtifact = nil
            lastRecordingURL = nil
            lastTranscriptURL = nil
        }
        statusMessage = mode == .transcribe
            ? "Starting \(source.title.lowercased()) capture with \(provider.title)..."
            : "Starting \(source.title.lowercased()) capture..."

        Task { [weak self] in
            guard let self else { return }
            do {
                if mode == .transcribe {
                    let supportsRealtime = await transcriptionService.supportsRealtime(providerID: provider)
                    if supportsRealtime {
                        statusMessage = "Realtime transcription ready."
                    }
                }
                let startedAt = try await captureService.startRecording(source: source)
                await MainActor.run {
                    self.activeStartedAt = startedAt
                    self.state = .recording(startedAt: startedAt)
                    self.statusMessage = mode == .transcribe ? "Recording for transcription with \(provider.title)..." : "Recording..."
                    if isChatInput {
                        self.chatVoiceStatusMessage = "Recording with \(provider.title). Press the microphone again to stop."
                    }
                }
            } catch {
                await MainActor.run {
                    self.fail(error, isChatInput: isChatInput)
                }
            }
        }
        return true
    }

    private func stopSession(isChatInput: Bool) {
        guard isRecording else { return }
        let sessionIsChatInput = activeIsChatInput
        state = .transcribing
        statusMessage = activeMode == .transcribe
            ? "Stopping and transcribing with \(activeProvider.title)..."
            : "Stopping recording..."
        if sessionIsChatInput || isChatInput {
            chatVoiceStatusMessage = "Transcribing..."
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let stopped = try await captureService.stopRecording()
                await MainActor.run {
                    self.lastRecordingURL = stopped.url
                }

                if activeMode == .record {
                    await MainActor.run {
                        self.completeRecordingOnly(stopped.url, durationSeconds: stopped.durationSeconds, isChatInput: sessionIsChatInput)
                    }
                    return
                }

                let result = try await transcriptionService.transcribeFile(
                    stopped.url,
                    providerID: activeProvider
                )
                await MainActor.run {
                    self.completeTranscription(result, durationSeconds: stopped.durationSeconds, isChatInput: sessionIsChatInput)
                }
            } catch {
                await MainActor.run {
                    self.fail(error, isChatInput: sessionIsChatInput || isChatInput)
                }
            }
        }
    }

    private func completeRecordingOnly(_ url: URL, durationSeconds: Double?, isChatInput: Bool) {
        let artifact = AudioCaptureArtifact(
            artifactID: "audio-\(UUID().uuidString)",
            source: activeSource,
            providerID: activeProvider,
            audioPath: url.path,
            transcriptPath: nil,
            transcriptText: nil,
            durationSeconds: durationSeconds,
            status: "ready",
            errorCode: nil,
            errorMessage: nil,
            fallbackAttempted: false
        )
        lastArtifact = artifact
        state = .completed
        activeIsChatInput = false
        statusMessage = "Recording saved."
        if isChatInput {
            isChatVoiceInputActive = false
            chatVoiceStatusMessage = "Recording saved, but no transcript was requested."
        }
    }

    private func completeTranscription(
        _ result: SpeechTranscriptionResult,
        durationSeconds: Double?,
        isChatInput: Bool
    ) {
        transcriptText = result.transcriptText
        lastTranscriptURL = result.transcriptURL
        lastRecordingURL = result.audioURL
        lastArtifact = AudioCaptureArtifact(
            artifactID: "audio-transcript-\(UUID().uuidString)",
            source: activeSource,
            providerID: result.providerID,
            audioPath: result.audioURL?.path,
            transcriptPath: result.transcriptURL?.path,
            transcriptText: result.transcriptText,
            durationSeconds: durationSeconds ?? result.durationSeconds,
            status: result.status,
            errorCode: result.errorCode,
            errorMessage: result.errorMessage,
            fallbackAttempted: result.fallbackAttempted
        )
        state = .completed
        activeIsChatInput = false
        statusMessage = "Transcription completed."
        if isChatInput {
            chatVoiceText = result.transcriptText
            chatVoiceStatusMessage = "Voice input ready."
            isChatVoiceInputActive = false
        }
    }

    private func fail(_ error: Error, isChatInput: Bool) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        activeIsChatInput = false
        statusMessage = message
        lastArtifact = AudioCaptureArtifact(
            artifactID: "audio-failed-\(UUID().uuidString)",
            source: activeSource,
            providerID: activeProvider,
            audioPath: lastRecordingURL?.path,
            transcriptPath: nil,
            transcriptText: nil,
            durationSeconds: activeStartedAt.map { Date().timeIntervalSince($0) },
            status: "failed",
            errorCode: String(describing: type(of: error)),
            errorMessage: message,
            fallbackAttempted: false
        )
        if isChatInput {
            chatVoiceStatusMessage = message
            isChatVoiceInputActive = false
        }
    }
}
