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
    var statusMessage: String
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
    private var appLanguage: AppLanguage

    private static let providerPreferenceKey = "geeagent.audioCapture.transcriptionProvider"

    init(
        captureService: AudioCaptureService = AudioCaptureService(),
        transcriptionService: SpeechTranscriptionService = SpeechTranscriptionService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.captureService = captureService
        self.transcriptionService = transcriptionService
        self.userDefaults = userDefaults
        let appLanguage = AppLanguage.savedPreference(defaults: userDefaults)
        self.appLanguage = appLanguage
        self.statusMessage = AppLocalization.string("audio.status.ready", defaultValue: "Ready.", language: appLanguage)
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

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        refreshLocalizedStatusMessages()
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
            chatVoiceStatusMessage = localizedFormat(
                "audio.status.listeningWith",
                defaultValue: "Listening with %@...",
                selectedProvider.title
            )
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
        statusMessage = transcriptText.isEmpty
            ? localizedString("audio.status.noTranscriptToCopy", defaultValue: "No transcript to copy.")
            : localizedString("audio.status.transcriptCopied", defaultValue: "Transcript copied.")
    }

    func revealLastRecording() {
        guard let lastRecordingURL else {
            statusMessage = localizedString("audio.status.noSavedRecording", defaultValue: "No saved recording to reveal.")
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
            let message = localizedString("audio.status.alreadyActive", defaultValue: "Audio capture is already active.")
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
            ? localizedFormat(
                "audio.status.startingCaptureWithProvider",
                defaultValue: "Starting %@ capture with %@...",
                sourceTitle(source).lowercased(),
                provider.title
            )
            : localizedFormat(
                "audio.status.startingCapture",
                defaultValue: "Starting %@ capture...",
                sourceTitle(source).lowercased()
            )

        Task { [weak self] in
            guard let self else { return }
            do {
                if mode == .transcribe {
                    let supportsRealtime = await transcriptionService.supportsRealtime(providerID: provider)
                    if supportsRealtime {
                        statusMessage = localizedString("audio.status.realtimeReady", defaultValue: "Realtime transcription ready.")
                    }
                }
                let startedAt = try await captureService.startRecording(source: source)
                await MainActor.run {
                    self.activeStartedAt = startedAt
                    self.state = .recording(startedAt: startedAt)
                    self.statusMessage = mode == .transcribe
                        ? self.localizedFormat(
                            "audio.status.recordingForTranscription",
                            defaultValue: "Recording for transcription with %@...",
                            provider.title
                        )
                        : self.localizedString("audio.status.recording", defaultValue: "Recording...")
                    if isChatInput {
                        self.chatVoiceStatusMessage = self.localizedFormat(
                            "audio.status.chatRecordingWithProvider",
                            defaultValue: "Recording with %@. Press the microphone again to stop.",
                            provider.title
                        )
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
            ? localizedFormat(
                "audio.status.stoppingTranscribing",
                defaultValue: "Stopping and transcribing with %@...",
                activeProvider.title
            )
            : localizedString("audio.status.stoppingRecording", defaultValue: "Stopping recording...")
        if sessionIsChatInput || isChatInput {
            chatVoiceStatusMessage = localizedString("audio.status.transcribing", defaultValue: "Transcribing...")
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
        statusMessage = localizedString("audio.status.recordingSaved", defaultValue: "Recording saved.")
        if isChatInput {
            isChatVoiceInputActive = false
            chatVoiceStatusMessage = localizedString(
                "audio.status.recordingSavedNoTranscript",
                defaultValue: "Recording saved, but no transcript was requested."
            )
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
        statusMessage = localizedString("audio.status.transcriptionCompleted", defaultValue: "Transcription completed.")
        if isChatInput {
            chatVoiceText = result.transcriptText
            chatVoiceStatusMessage = localizedString("audio.status.voiceInputReady", defaultValue: "Voice input ready.")
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

    private func refreshLocalizedStatusMessages() {
        switch state {
        case .idle:
            statusMessage = localizedString("audio.status.ready", defaultValue: "Ready.")
        case .starting:
            statusMessage = activeMode == .transcribe
                ? localizedFormat(
                    "audio.status.startingCaptureWithProvider",
                    defaultValue: "Starting %@ capture with %@...",
                    sourceTitle(activeSource).lowercased(),
                    activeProvider.title
                )
                : localizedFormat(
                    "audio.status.startingCapture",
                    defaultValue: "Starting %@ capture...",
                    sourceTitle(activeSource).lowercased()
                )
        case .recording:
            statusMessage = activeMode == .transcribe
                ? localizedFormat(
                    "audio.status.recordingForTranscription",
                    defaultValue: "Recording for transcription with %@...",
                    activeProvider.title
                )
                : localizedString("audio.status.recording", defaultValue: "Recording...")
        case .transcribing:
            statusMessage = activeMode == .transcribe
                ? localizedFormat(
                    "audio.status.stoppingTranscribing",
                    defaultValue: "Stopping and transcribing with %@...",
                    activeProvider.title
                )
                : localizedString("audio.status.stoppingRecording", defaultValue: "Stopping recording...")
        case .completed:
            statusMessage = transcriptText.isEmpty
                ? localizedString("audio.status.recordingSaved", defaultValue: "Recording saved.")
                : localizedString("audio.status.transcriptionCompleted", defaultValue: "Transcription completed.")
        case .failed:
            break
        }

        if isChatVoiceInputActive {
            switch state {
            case .starting:
                chatVoiceStatusMessage = localizedFormat(
                    "audio.status.listeningWith",
                    defaultValue: "Listening with %@...",
                    activeProvider.title
                )
            case .recording:
                chatVoiceStatusMessage = localizedFormat(
                    "audio.status.chatRecordingWithProvider",
                    defaultValue: "Recording with %@. Press the microphone again to stop.",
                    activeProvider.title
                )
            case .transcribing:
                chatVoiceStatusMessage = localizedString("audio.status.transcribing", defaultValue: "Transcribing...")
            default:
                break
            }
        } else if chatVoiceStatusMessage != nil, !chatVoiceText.isEmpty {
            chatVoiceStatusMessage = localizedString("audio.status.voiceInputReady", defaultValue: "Voice input ready.")
        }
    }

    private func localizedString(_ key: String, defaultValue: String) -> String {
        AppLocalization.string(key, defaultValue: defaultValue, language: appLanguage)
    }

    private func localizedFormat(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        AppLocalization.format(key, defaultValue: defaultValue, language: appLanguage, arguments: arguments)
    }

    private func sourceTitle(_ source: AudioCaptureSource) -> String {
        switch source {
        case .microphone:
            AppLocalization.string("audio.source.microphone", defaultValue: "Microphone", language: appLanguage)
        case .systemAudio:
            AppLocalization.string("audio.source.systemAudio", defaultValue: "System Audio", language: appLanguage)
        }
    }
}
