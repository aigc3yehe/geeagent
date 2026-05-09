import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

protocol MicrophonePermissionChecking: Sendable {
    func authorizationStatus() -> AudioCaptureAuthorizationStatus
    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult
    var permissionContext: AudioCapturePermissionContext { get }
}

private final class AudioCapturePermissionRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<AudioCapturePermissionRequestResult, Never>,
        with result: AudioCapturePermissionRequestResult
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: result)
    }
}

struct SystemMicrophonePermissionChecker: MicrophonePermissionChecking {
    var permissionContext: AudioCapturePermissionContext {
        AudioCapturePermissionContext.current
    }

    func authorizationStatus() -> AudioCaptureAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult {
        await withCheckedContinuation { continuation in
            let gate = AudioCapturePermissionRequestGate()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                gate.resume(continuation, with: granted ? .granted : .denied)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutSeconds) {
                gate.resume(continuation, with: .timedOut)
            }
        }
    }
}

protocol ScreenRecordingPermissionChecking: Sendable {
    func authorizationStatus() -> AudioCaptureAuthorizationStatus
    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult
    var permissionContext: AudioCapturePermissionContext { get }
}

struct SystemScreenRecordingPermissionChecker: ScreenRecordingPermissionChecking {
    var permissionContext: AudioCapturePermissionContext {
        AudioCapturePermissionContext.current
    }

    func authorizationStatus() -> AudioCaptureAuthorizationStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined
    }

    func requestAccess(timeoutSeconds: TimeInterval) async -> AudioCapturePermissionRequestResult {
        let granted = await MainActor.run {
            CGRequestScreenCaptureAccess()
        }
        return granted ? .granted : .denied
    }
}

actor AudioCaptureService {
    private var activeRecorder: AVAudioRecorder?
    private var activeSystemAudioSession: SystemAudioCaptureSessioning?
    private var activeRecordingURL: URL?
    private var activeStartedAt: Date?
    private let microphonePermissionChecker: MicrophonePermissionChecking
    private let screenRecordingPermissionChecker: ScreenRecordingPermissionChecking
    private let systemAudioSessionMaker: SystemAudioCaptureSessionMaking
    private let permissionRequestTimeoutSeconds: TimeInterval

    init(
        microphonePermissionChecker: MicrophonePermissionChecking = SystemMicrophonePermissionChecker(),
        screenRecordingPermissionChecker: ScreenRecordingPermissionChecking = SystemScreenRecordingPermissionChecker(),
        systemAudioSessionMaker: SystemAudioCaptureSessionMaking = ScreenCaptureKitSystemAudioSessionMaker(),
        permissionRequestTimeoutSeconds: TimeInterval = 8
    ) {
        self.microphonePermissionChecker = microphonePermissionChecker
        self.screenRecordingPermissionChecker = screenRecordingPermissionChecker
        self.systemAudioSessionMaker = systemAudioSessionMaker
        self.permissionRequestTimeoutSeconds = permissionRequestTimeoutSeconds
    }

    func startRecording(source: AudioCaptureSource) async throws -> Date {
        guard activeRecorder == nil, activeSystemAudioSession == nil else {
            throw AudioCaptureError.recordingAlreadyActive
        }

        switch source {
        case .microphone:
            return try await startMicrophoneRecording()
        case .systemAudio:
            return try await startSystemAudioRecording()
        }
    }

    func stopRecording() async throws -> (url: URL, startedAt: Date?, durationSeconds: Double?) {
        if let recorder = activeRecorder,
           let url = activeRecordingURL {
            let startedAt = activeStartedAt
            recorder.stop()
            activeRecorder = nil
            activeRecordingURL = nil
            activeStartedAt = nil

            let duration = startedAt.map { Date().timeIntervalSince($0) }
            return (url, startedAt, duration)
        }

        if let session = activeSystemAudioSession {
            let startedAt = activeStartedAt
            defer {
                activeSystemAudioSession = nil
                activeRecordingURL = nil
                activeStartedAt = nil
            }
            let stopped = try await session.stop()
            return (stopped.url, startedAt, stopped.durationSeconds)
        }

        throw AudioCaptureError.noActiveRecording
    }

    private func startSystemAudioRecording() async throws -> Date {
        let directory = try Self.captureDirectory()
        let url = directory.appendingPathComponent(Self.recordingFileName(source: .systemAudio), isDirectory: false)
        let session = systemAudioSessionMaker.make(outputURL: url)
        do {
            let startedAt = try await session.start()
            activeSystemAudioSession = session
            activeRecordingURL = url
            activeStartedAt = startedAt
            return startedAt
        } catch let error as AudioCaptureError {
            throw error
        } catch {
            throw Self.systemAudioError(from: error)
        }
    }

    fileprivate static func systemAudioError(from error: Error) -> AudioCaptureError {
        let nsError = error as NSError
        let detail = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog(
            "GeeAgent system audio start failed: domain=%@ code=%d detail=%@",
            nsError.domain,
            nsError.code,
            detail.isEmpty ? "empty" : detail
        )
        let permissionNeedles = [
            "screen recording",
            "not authorized",
            "permission",
            "TCC"
        ]
        if permissionNeedles.contains(where: { detail.localizedCaseInsensitiveContains($0) }) {
            return .systemAudioPermissionDenied(
                AudioCapturePermissionIssue(
                    kind: .screenRecording,
                    status: .denied,
                    context: .current
                )
            )
        }
        return .systemAudioCaptureUnavailable(
            detail.isEmpty ? "System audio capture failed before recording could start." : detail
        )
    }

    private func startMicrophoneRecording() async throws -> Date {
        try await ensureMicrophoneAccess()

        let directory = try Self.captureDirectory()
        let url = directory.appendingPathComponent(Self.recordingFileName(source: .microphone), isDirectory: false)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioCaptureError.recordingDidNotStart
        }

        let startedAt = Date()
        activeRecorder = recorder
        activeRecordingURL = url
        activeStartedAt = startedAt
        return startedAt
    }

    private func ensureMicrophoneAccess() async throws {
        let status = microphonePermissionChecker.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let result = await microphonePermissionChecker.requestAccess(timeoutSeconds: permissionRequestTimeoutSeconds)
            if result == .granted || microphonePermissionChecker.authorizationStatus() == .authorized {
                return
            }
            let refreshedStatus = microphonePermissionChecker.authorizationStatus()
            if result == .timedOut {
                throw permissionRequestTimedOut(
                    kind: .microphone,
                    status: refreshedStatus,
                    context: microphonePermissionChecker.permissionContext
                )
            }
            throw microphonePermissionError(status: refreshedStatus)
        case .denied, .restricted, .unknown:
            throw microphonePermissionError(status: status)
        }
    }

    private func microphonePermissionError(status: AudioCaptureAuthorizationStatus) -> AudioCaptureError {
        .microphonePermissionDenied(
            AudioCapturePermissionIssue(
                kind: .microphone,
                status: status,
                context: microphonePermissionChecker.permissionContext
            )
        )
    }

    private func ensureSystemAudioAccess() async throws {
        let status = screenRecordingPermissionChecker.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let result = await screenRecordingPermissionChecker.requestAccess(timeoutSeconds: permissionRequestTimeoutSeconds)
            if result == .granted || screenRecordingPermissionChecker.authorizationStatus() == .authorized {
                return
            }
            if result == .timedOut {
                throw permissionRequestTimedOut(
                    kind: .screenRecording,
                    status: screenRecordingPermissionChecker.authorizationStatus(),
                    context: screenRecordingPermissionChecker.permissionContext
                )
            }
            throw systemAudioPermissionError(status: .denied)
        case .denied, .restricted, .unknown:
            throw systemAudioPermissionError(status: status)
        }
    }

    private func permissionRequestTimedOut(
        kind: AudioCapturePermissionKind,
        status: AudioCaptureAuthorizationStatus,
        context: AudioCapturePermissionContext
    ) -> AudioCaptureError {
        .permissionRequestTimedOut(
            AudioCapturePermissionIssue(
                kind: kind,
                status: status,
                context: context
            ),
            seconds: permissionRequestTimeoutSeconds
        )
    }

    private func systemAudioPermissionError(status: AudioCaptureAuthorizationStatus) -> AudioCaptureError {
        .systemAudioPermissionDenied(
            AudioCapturePermissionIssue(
                kind: .screenRecording,
                status: status,
                context: screenRecordingPermissionChecker.permissionContext
            )
        )
    }

    private static func captureDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("GeeAgent", isDirectory: true)
            .appendingPathComponent("AudioCaptures", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/GeeAgent/AudioCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func recordingFileName(source: AudioCaptureSource) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let sourceLabel = source == .systemAudio ? "system-audio" : "microphone"
        return "geeagent-\(sourceLabel)-\(stamp).wav"
    }
}

protocol SystemAudioCaptureSessioning: AnyObject, Sendable {
    func start() async throws -> Date
    func stop() async throws -> (url: URL, durationSeconds: Double?)
}

protocol SystemAudioCaptureSessionMaking: Sendable {
    func make(outputURL: URL) -> SystemAudioCaptureSessioning
}

struct ScreenCaptureKitSystemAudioSessionMaker: SystemAudioCaptureSessionMaking {
    func make(outputURL: URL) -> SystemAudioCaptureSessioning {
        ScreenCaptureKitSystemAudioSession(outputURL: outputURL)
    }
}

private final class ScreenCaptureKitSystemAudioSession: NSObject, SystemAudioCaptureSessioning, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputURL: URL
    private let sampleQueue = DispatchQueue(label: "geeagent.system-audio.samples")
    private let lock = NSLock()
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstSampleTime: CMTime?
    private var startedAt: Date?
    private var pendingStopContinuation: CheckedContinuation<Void, Never>?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start() async throws -> Date {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw AudioCaptureService.systemAudioError(from: error)
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.systemAudioCaptureUnavailable("No active display was available for system audio capture.")
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        // macOS 15 separates "Screen & System Audio Recording" from
        // "System Audio Recording Only". GeeAgent's Settings guidance points
        // users at the former, so attach a tiny screen output and discard its
        // frames. Audio is the only persisted artifact.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        let startedAt = Date()
        lock.withLock {
            self.stream = stream
            self.startedAt = startedAt
        }
        return startedAt
    }

    func stop() async throws -> (url: URL, durationSeconds: Double?) {
        let localStream = lock.withLock { stream }
        guard let localStream else {
            throw AudioCaptureError.noActiveRecording
        }

        try await localStream.stopCapture()
        await waitForWriterFinishIfNeeded()
        let startedAt = lock.withLock { self.startedAt }
        lock.withLock {
            self.stream = nil
            self.writer = nil
            self.input = nil
            self.firstSampleTime = nil
            self.startedAt = nil
        }
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        return (outputURL, duration)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        do {
            let writerInput = try ensureWriter(for: sampleBuffer)
            guard writerInput.isReadyForMoreMediaData else {
                return
            }
            writerInput.append(sampleBuffer)
        } catch {
            NSLog("GeeAgent system audio writer failed: \(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("GeeAgent system audio stream stopped with error: \(error.localizedDescription)")
        finishWriter()
    }

    private func ensureWriter(for sampleBuffer: CMSampleBuffer) throws -> AVAssetWriterInput {
        try lock.withLock {
            if let input {
                return input
            }
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw AudioCaptureError.systemAudioCaptureUnavailable("System audio sample format was unavailable.")
            }
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: outputSettings,
                sourceFormatHint: formatDescription
            )
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw AudioCaptureError.systemAudioCaptureUnavailable("System audio writer could not accept the capture input.")
            }
            writer.add(input)
            let firstTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: firstTime)
            self.writer = writer
            self.input = input
            self.firstSampleTime = firstTime
            return input
        }
    }

    private func finishWriter() {
        let writerAndInput = lock.withLock { () -> (AVAssetWriter?, AVAssetWriterInput?) in
            (writer, input)
        }
        guard let writer = writerAndInput.0, let input = writerAndInput.1 else {
            resumeStopWaiter()
            return
        }
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            self?.resumeStopWaiter()
        }
    }

    private func waitForWriterFinishIfNeeded() async {
        let hasWriter = lock.withLock { writer != nil }
        guard hasWriter else { return }
        await withCheckedContinuation { continuation in
            let shouldWait = lock.withLock {
                if pendingStopContinuation == nil {
                    pendingStopContinuation = continuation
                    return true
                }
                return false
            }
            if shouldWait {
                finishWriter()
            } else {
                continuation.resume()
            }
        }
    }

    private func resumeStopWaiter() {
        let continuation = lock.withLock {
            let continuation = pendingStopContinuation
            pendingStopContinuation = nil
            return continuation
        }
        continuation?.resume()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
