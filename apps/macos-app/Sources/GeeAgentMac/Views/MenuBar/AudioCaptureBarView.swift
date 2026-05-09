import SwiftUI

struct AudioCaptureBarView: View {
    @Bindable var audio: AudioCaptureCoordinator
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            transcriptArea
            footer
        }
        .padding(14)
        .frame(width: 680, alignment: .topLeading)
        .background(panelBackground)
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Capture")
                    .font(.geeDisplaySemibold(15))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Control + Option + A or Shift + Command + A")
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            Text(audio.state.title)
                .font(.geeBodyMedium(11))
                .foregroundStyle(stateTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateTint.opacity(0.14), in: Capsule())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.66))
            .help("Close audio bar")
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Source", selection: $audio.selectedSource) {
                ForEach(AudioCaptureSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage).tag(source)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            .disabled(audio.state.isActive)

            Picker("Mode", selection: $audio.selectedMode) {
                ForEach(AudioCaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 184)
            .disabled(audio.state.isActive)

            HStack(spacing: 6) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 11, weight: .semibold))
                Text(audio.selectedProvider.title)
                    .lineLimit(1)
            }
            .font(.geeBodyMedium(11))
            .foregroundStyle(.white.opacity(audio.selectedMode == .record ? 0.34 : 0.72))
            .frame(width: 164, height: 28)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help("Default STT service. Change this in Settings > Speech To Text.")

            Spacer(minLength: 4)

            if audio.canStop {
                Button(action: audio.stopBarSession) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            } else {
                Button(action: audio.startBarSession) {
                    Label("Start", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!audio.canStart)
            }
        }
    }

    private var transcriptArea: some View {
        ScrollView {
            Text(resultText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(audio.transcriptText.isEmpty ? 0.5 : 0.88))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(height: 112)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(audio.statusMessage)
                .font(.geeBody(11))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)

            if let path = audio.lastRecordingURL?.path {
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: audio.revealLastRecording) {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.geeBodyMedium(11))
            .foregroundStyle(.white.opacity(audio.lastRecordingURL == nil ? 0.34 : 0.82))
            .disabled(audio.lastRecordingURL == nil)

            Button(action: audio.copyTranscriptToPasteboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .font(.geeBodyMedium(11))
            .foregroundStyle(.white.opacity(audio.transcriptText.isEmpty ? 0.34 : 0.82))
            .disabled(audio.transcriptText.isEmpty)
        }
    }

    private var resultText: String {
        if !audio.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return audio.transcriptText
        }
        switch audio.state {
        case .idle:
            return "Transcript output will appear here."
        case .starting:
            return "Starting audio capture..."
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .completed:
            return "Recording saved."
        case let .failed(message):
            return message
        }
    }

    private var stateTint: Color {
        switch audio.state {
        case .idle:
            return .secondary
        case .starting:
            return .blue
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .orange
        }
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.045, green: 0.05, blue: 0.064))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.9)
        }
        .allowsHitTesting(false)
    }
}
