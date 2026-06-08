import XCTest
@testable import GeeAgentMac

final class AudioCaptureModelsTests: XCTestCase {
    func testStartingStateBlocksAdditionalStarts() {
        XCTAssertTrue(AudioCaptureState.starting.isActive)
        XCTAssertEqual(AudioCaptureState.starting.title, "Starting")
    }

    func testIdleAndCompletedStatesAreNotActive() {
        XCTAssertFalse(AudioCaptureState.idle.isActive)
        XCTAssertFalse(AudioCaptureState.completed.isActive)
    }

    func testSystemAudioPermissionErrorPointsAtScreenRecording() {
        let issue = AudioCapturePermissionIssue(
            kind: .screenRecording,
            status: .denied,
            context: AudioCapturePermissionContext(
                bundleIdentifier: "com.geeagent.GeeAgentMac",
                executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
                hasMicrophoneUsageDescription: true
            )
        )

        let message = AudioCaptureError.systemAudioPermissionDenied(issue).errorDescription ?? ""

        XCTAssertTrue(message.contains("screen recording and system audio"))
        XCTAssertTrue(message.contains("Screen & System Audio Recording"))
        XCTAssertTrue(message.contains("com.geeagent.GeeAgentMac"))
    }

    func testMicrophonePermissionErrorIncludesTCCContext() {
        let issue = AudioCapturePermissionIssue(
            status: .denied,
            context: AudioCapturePermissionContext(
                bundleIdentifier: "com.geeagent.GeeAgentMac",
                executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
                hasMicrophoneUsageDescription: true
            )
        )

        let message = AudioCaptureError.microphonePermissionDenied(issue).errorDescription ?? ""

        XCTAssertTrue(message.contains("Denied"))
        XCTAssertTrue(message.contains("com.geeagent.GeeAgentMac"))
        XCTAssertTrue(message.contains("/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac"))
        XCTAssertTrue(message.contains("quit and reopen"))
    }

    func testMicrophonePermissionErrorCallsOutMissingUsageDescription() {
        let issue = AudioCapturePermissionIssue(
            status: .denied,
            context: AudioCapturePermissionContext(
                bundleIdentifier: "com.geeagent.GeeAgentMac",
                executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
                hasMicrophoneUsageDescription: false
            )
        )

        XCTAssertEqual(
            AudioCaptureError.microphonePermissionDenied(issue).errorDescription,
            "This GeeAgent app bundle is missing NSMicrophoneUsageDescription, so macOS will not grant microphone access. Rebuild and launch the packaged GeeAgentMac.app."
        )
    }

    func testRecordingAlreadyActiveErrorIsStructured() {
        XCTAssertEqual(
            AudioCaptureError.recordingAlreadyActive.errorDescription,
            "Audio capture is already active."
        )
    }

    func testPermissionRequestTimeoutMentionsStaleTCCEntry() {
        let issue = AudioCapturePermissionIssue(
            status: .notDetermined,
            context: AudioCapturePermissionContext(
                bundleIdentifier: "com.geeagent.GeeAgentMac",
                executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
                hasMicrophoneUsageDescription: true
            )
        )

        let message = AudioCaptureError.permissionRequestTimedOut(issue, seconds: 8).errorDescription ?? ""

        XCTAssertTrue(message.contains("within 8 seconds"))
        XCTAssertTrue(message.contains("stale TCC entry"))
        XCTAssertTrue(message.contains("com.geeagent.GeeAgentMac"))
    }

    func testSenseVoiceProviderDescribesGlobalCommand() {
        XCTAssertEqual(SpeechTranscriptionProviderID.localSenseVoice.title, "Local SenseVoice")
        XCTAssertTrue(SpeechTranscriptionProviderID.localSenseVoice.detail.contains("sensevoice-transcribe"))
    }

    func testMicrophoneDeniedStopsBeforeRecordingStarts() async throws {
        let checker = MockMicrophonePermissionChecker(status: .denied)
        let service = AudioCaptureService(microphonePermissionChecker: checker)

        do {
            _ = try await service.startRecording(source: .microphone)
            XCTFail("Expected microphone permission denial to stop recording startup.")
        } catch AudioCaptureError.microphonePermissionDenied(let issue) {
            XCTAssertEqual(issue.status, .denied)
            XCTAssertEqual(issue.context.bundleIdentifier, "com.geeagent.GeeAgentMac")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSystemAudioDoesNotTrustPreflightDenialOverScreenCaptureKit() async throws {
        let checker = MockScreenRecordingPermissionChecker(status: .denied)
        let session = MockSystemAudioSession(startedAt: Date(timeIntervalSinceReferenceDate: 100))
        let service = AudioCaptureService(
            screenRecordingPermissionChecker: checker,
            systemAudioSessionMaker: MockSystemAudioSessionMaker(session: session)
        )

        let startedAt = try await service.startRecording(source: .systemAudio)

        XCTAssertEqual(startedAt, session.startedAt)
        XCTAssertTrue(session.didStart)
    }

    func testMicrophonePermissionTimeoutStopsStartup() async throws {
        let checker = MockMicrophonePermissionChecker(status: .notDetermined, requestResult: .timedOut)
        let service = AudioCaptureService(
            microphonePermissionChecker: checker,
            permissionRequestTimeoutSeconds: 1
        )

        do {
            _ = try await service.startRecording(source: .microphone)
            XCTFail("Expected microphone permission timeout to stop recording startup.")
        } catch AudioCaptureError.permissionRequestTimedOut(let issue, let seconds) {
            XCTAssertEqual(issue.kind, .microphone)
            XCTAssertEqual(issue.status, .notDetermined)
            XCTAssertEqual(seconds, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDefaultSpeechProviderPersistsForSharedChatAndBarUse() {
        let suiteName = "GeeAgentAudioCaptureCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstCoordinator = AudioCaptureCoordinator(userDefaults: defaults)
        firstCoordinator.selectedProvider = .localSenseVoice

        let secondCoordinator = AudioCaptureCoordinator(userDefaults: defaults)

        XCTAssertEqual(secondCoordinator.selectedProvider, .localSenseVoice)
    }

    @MainActor
    func testCoordinatorStatusRefreshesWhenAppLanguageChanges() {
        let suiteName = "GeeAgentAudioCaptureCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguage.save(.en, defaults: defaults)
        let coordinator = AudioCaptureCoordinator(userDefaults: defaults)

        XCTAssertEqual(coordinator.statusMessage, "Ready.")

        coordinator.setAppLanguage(.ja)

        XCTAssertFalse(coordinator.statusMessage.isEmpty)
        XCTAssertNotEqual(coordinator.statusMessage, "Ready.")
    }
}

private struct MockMicrophonePermissionChecker: MicrophonePermissionChecking {
    var status: AudioCaptureAuthorizationStatus
    var requestResult: AudioCapturePermissionRequestResult = .denied

    var permissionContext: AudioCapturePermissionContext {
        AudioCapturePermissionContext(
            bundleIdentifier: "com.geeagent.GeeAgentMac",
            executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
            hasMicrophoneUsageDescription: true
        )
    }

    func authorizationStatus() -> AudioCaptureAuthorizationStatus {
        status
    }

    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult {
        requestResult
    }
}

private struct MockScreenRecordingPermissionChecker: ScreenRecordingPermissionChecking {
    var status: AudioCaptureAuthorizationStatus
    var requestResult: AudioCapturePermissionRequestResult = .denied

    var permissionContext: AudioCapturePermissionContext {
        AudioCapturePermissionContext(
            bundleIdentifier: "com.geeagent.GeeAgentMac",
            executablePath: "/Applications/GeeAgentMac.app/Contents/MacOS/GeeAgentMac",
            hasMicrophoneUsageDescription: true
        )
    }

    func authorizationStatus() -> AudioCaptureAuthorizationStatus {
        status
    }

    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult {
        requestResult
    }
}

private struct MockSystemAudioSessionMaker: SystemAudioCaptureSessionMaking {
    let session: MockSystemAudioSession

    func make(outputURL: URL) -> SystemAudioCaptureSessioning {
        session
    }
}

private final class MockSystemAudioSession: SystemAudioCaptureSessioning, @unchecked Sendable {
    let startedAt: Date
    private(set) var didStart = false

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    func start() async throws -> Date {
        didStart = true
        return startedAt
    }

    func stop() async throws -> (url: URL, durationSeconds: Double?) {
        (URL(fileURLWithPath: "/tmp/geeagent-system-audio.wav"), 0)
    }
}
