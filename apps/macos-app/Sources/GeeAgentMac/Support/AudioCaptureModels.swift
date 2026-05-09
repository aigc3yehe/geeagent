import Foundation

enum AudioCaptureSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic"
        case .systemAudio: "speaker.wave.2"
        }
    }
}

enum AudioCaptureMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case record
    case transcribe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Record"
        case .transcribe: "Transcribe"
        }
    }
}

enum SpeechTranscriptionProviderID: String, CaseIterable, Identifiable, Codable, Hashable {
    case localWhisper
    case localSenseVoice
    case elevenLabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localWhisper: "Local Whisper"
        case .localSenseVoice: "Local SenseVoice"
        case .elevenLabs: "ElevenLabs"
        }
    }

    var detail: String {
        switch self {
        case .localWhisper:
            "Uses local faster-whisper, whisper, or whisper-cli when installed."
        case .localSenseVoice:
            "Uses the global sensevoice-transcribe command when installed."
        case .elevenLabs:
            "Uses the saved ElevenLabs key from Settings for online speech-to-text."
        }
    }
}

enum AudioCaptureState: Equatable, Hashable {
    case idle
    case starting
    case recording(startedAt: Date)
    case transcribing
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .recording, .transcribing:
            true
        case .idle, .completed, .failed:
            false
        }
    }
}

struct AudioCaptureArtifact: Codable, Hashable, Sendable {
    var artifactID: String
    var source: AudioCaptureSource
    var providerID: SpeechTranscriptionProviderID
    var audioPath: String?
    var transcriptPath: String?
    var transcriptText: String?
    var durationSeconds: Double?
    var status: String
    var errorCode: String?
    var errorMessage: String?
    var fallbackAttempted: Bool
}

struct SpeechTranscriptionResult: Hashable, Sendable {
    var providerID: SpeechTranscriptionProviderID
    var transcriptText: String
    var transcriptURL: URL?
    var audioURL: URL?
    var durationSeconds: Double?
    var status: String
    var errorCode: String?
    var errorMessage: String?
    var fallbackAttempted: Bool
}

enum AudioCaptureAuthorizationStatus: String, Equatable, Hashable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown

    var title: String {
        switch self {
        case .authorized: "Authorized"
        case .notDetermined: "Not Determined"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .unknown: "Unknown"
        }
    }
}

enum AudioCapturePermissionRequestResult: Equatable, Hashable, Sendable {
    case granted
    case denied
    case timedOut
}

struct AudioCapturePermissionContext: Equatable, Hashable, Sendable {
    var bundleIdentifier: String
    var executablePath: String
    var hasMicrophoneUsageDescription: Bool

    static let unavailableValue = "unavailable"

    static var current: AudioCapturePermissionContext {
        let bundle = Bundle.main
        let usageDescription = bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        return AudioCapturePermissionContext(
            bundleIdentifier: bundle.bundleIdentifier ?? unavailableValue,
            executablePath: bundle.executablePath ?? unavailableValue,
            hasMicrophoneUsageDescription: usageDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }

    var displayBundleIdentifier: String {
        bundleIdentifier == Self.unavailableValue ? "unknown bundle id" : bundleIdentifier
    }

    var displayExecutablePath: String {
        executablePath == Self.unavailableValue ? "unknown executable path" : executablePath
    }
}

enum AudioCapturePermissionKind: String, Equatable, Hashable, Sendable {
    case microphone
    case screenRecording

    var displayName: String {
        switch self {
        case .microphone: "microphone"
        case .screenRecording: "screen recording and system audio"
        }
    }

    var settingsPath: String {
        switch self {
        case .microphone: "System Settings > Privacy & Security > Microphone"
        case .screenRecording: "System Settings > Privacy & Security > Screen & System Audio Recording"
        }
    }

    var usageDescriptionKey: String {
        switch self {
        case .microphone: "NSMicrophoneUsageDescription"
        case .screenRecording: "ScreenCaptureKit permission"
        }
    }
}

struct AudioCapturePermissionIssue: Equatable, Hashable, Sendable {
    var kind: AudioCapturePermissionKind
    var status: AudioCaptureAuthorizationStatus
    var context: AudioCapturePermissionContext

    init(
        kind: AudioCapturePermissionKind = .microphone,
        status: AudioCaptureAuthorizationStatus,
        context: AudioCapturePermissionContext
    ) {
        self.kind = kind
        self.status = status
        self.context = context
    }

    var userFacingMessage: String {
        if kind == .microphone, !context.hasMicrophoneUsageDescription {
            return "This GeeAgent app bundle is missing NSMicrophoneUsageDescription, so macOS will not grant microphone access. Rebuild and launch the packaged GeeAgentMac.app."
        }

        switch status {
        case .denied:
            return "macOS is still reporting \(kind.displayName) access as Denied for GeeAgentMac (\(context.displayBundleIdentifier)). Enable \(kind.settingsPath), then quit and reopen this exact app: \(context.displayExecutablePath). If the toggle is already enabled, remove the stale GeeAgentMac permission entry or reset \(kind.displayName) permission for \(context.displayBundleIdentifier), then grant it again."
        case .restricted:
            return "macOS is restricting \(kind.displayName) access for GeeAgentMac (\(context.displayBundleIdentifier)). Check Screen Time, MDM, or privacy policy restrictions for this Mac."
        case .notDetermined:
            return "macOS did not finish granting \(kind.displayName) access to GeeAgentMac (\(context.displayBundleIdentifier)). Start recording again and accept the \(kind.displayName) prompt, then reopen GeeAgent if the prompt was handled while the app was already running."
        case .unknown:
            return "macOS returned an unknown \(kind.displayName) authorization state for GeeAgentMac (\(context.displayBundleIdentifier)). Quit and reopen \(context.displayExecutablePath), then try again."
        case .authorized:
            return "GeeAgent has \(kind.displayName) permission, but macOS still refused to start recording. Check the selected source and try again."
        }
    }
}

enum AudioCaptureError: LocalizedError, Equatable {
    case microphonePermissionDenied(AudioCapturePermissionIssue)
    case systemAudioPermissionDenied(AudioCapturePermissionIssue)
    case permissionRequestTimedOut(AudioCapturePermissionIssue, seconds: TimeInterval)
    case systemAudioCaptureUnavailable(String)
    case recordingAlreadyActive
    case recordingDidNotStart
    case noActiveRecording
    case noSpeechDetected(String)
    case providerUnavailable(String)
    case realtimeUnsupported(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .microphonePermissionDenied(issue):
            issue.userFacingMessage
        case let .systemAudioPermissionDenied(issue):
            issue.userFacingMessage
        case let .permissionRequestTimedOut(issue, seconds):
            "macOS did not return a \(issue.kind.displayName) permission result for GeeAgentMac (\(issue.context.displayBundleIdentifier)) within \(Int(seconds)) seconds. The privacy toggle may be a stale TCC entry from an older GeeAgentMac build. Enable \(issue.kind.settingsPath), then quit and reopen this exact app: \(issue.context.displayExecutablePath). If it is already enabled, remove or reset the GeeAgentMac entry for \(issue.context.displayBundleIdentifier), grant it again, and start recording once more."
        case let .systemAudioCaptureUnavailable(detail):
            detail
        case .recordingAlreadyActive:
            "Audio capture is already active."
        case .recordingDidNotStart:
            "GeeAgent could not start the audio recorder."
        case .noActiveRecording:
            "No active recording is available to stop."
        case let .noSpeechDetected(detail):
            detail
        case let .providerUnavailable(detail):
            detail
        case let .realtimeUnsupported(detail):
            detail
        case let .transcriptionFailed(detail):
            detail
        }
    }
}
