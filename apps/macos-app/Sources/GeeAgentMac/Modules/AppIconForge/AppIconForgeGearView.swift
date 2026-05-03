import AppKit
import SwiftUI

struct AppIconForgeGearModuleView: View {
    var body: some View {
        AppIconForgeGearWindow()
    }
}

struct AppIconForgeGearWindow: View {
    @StateObject private var store = AppIconForgeGearStore.shared

    var body: some View {
        ZStack {
            AppIconForgeBackdrop()
            HStack(spacing: 0) {
                controls
                    .frame(width: 380)
                Divider()
                    .overlay(Color.white.opacity(0.08))
                preview
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.9))
                    Text("App Icon Forge")
                        .font(.system(size: 27, weight: .semibold))
                }
                Text("Build a rounded macOS icon package from one image.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 10) {
                AppIconForgeSectionLabel("Input")
                Button {
                    store.chooseSourceImage()
                } label: {
                    Label(store.sourceURL?.lastPathComponent ?? "Choose image", systemImage: "photo")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(AppIconForgeControlButtonStyle(accent: .cyan))

                if let sourceURL = store.sourceURL {
                    Text(sourceURL.path)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                AppIconForgeSectionLabel("Output")
                TextField("AppIcon", text: $store.outputName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }

                Button {
                    store.chooseOutputDirectory()
                } label: {
                    Label(store.outputDirectory?.lastPathComponent ?? "Default export folder", systemImage: "folder")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(AppIconForgeControlButtonStyle())
            }

            VStack(alignment: .leading, spacing: 14) {
                AppIconForgeSectionLabel("Shape")
                AppIconForgeSliderRow(
                    title: "Scale",
                    value: $store.contentScale,
                    range: 0.60...0.95,
                    display: "\(Int(store.contentScale * 100))%"
                )
                AppIconForgeSliderRow(
                    title: "Radius",
                    value: $store.cornerRadiusRatio,
                    range: 0.08...0.28,
                    display: "\(Int(store.cornerRadiusRatio * 100))%"
                )
                Toggle(isOn: $store.includesShadow) {
                    Label("Shadow", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
            }

            Button {
                store.exportCurrent()
            } label: {
                Label(store.isExporting ? "Exporting" : "Export Icons", systemImage: store.isExporting ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppIconForgePrimaryButtonStyle())
            .disabled(store.isExporting || store.sourceURL == nil)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: store.errorMessage == nil ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.errorMessage == nil ? .green : .orange)
                    Text(store.errorMessage == nil ? "Ready" : "Attention")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(store.errorMessage ?? store.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.20))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.system(size: 22, weight: .semibold))
                    Text("1024 canvas, transparent padding, rounded icon body")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Spacer()
                if store.result != nil {
                    Button {
                        store.revealResult()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(AppIconForgeIconButtonStyle())
                    .help("Reveal output")
                }
            }

            HStack(alignment: .center, spacing: 26) {
                AppIconForgePreviewTile(image: store.previewImage, size: 256, label: "Large")
                VStack(alignment: .leading, spacing: 16) {
                    AppIconForgePreviewTile(image: store.previewImage, size: 96, label: "Dock")
                    AppIconForgePreviewTile(image: store.previewImage, size: 48, label: "List")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)

            if let result = store.result {
                VStack(alignment: .leading, spacing: 8) {
                    AppIconForgeResultRow(title: "ICNS", path: result.icnsURL.path)
                    AppIconForgeResultRow(title: "Iconset", path: result.iconsetURL.path)
                    AppIconForgeResultRow(title: "Xcode", path: result.appiconsetURL.path)
                    AppIconForgeResultRow(title: "Preview", path: result.previewURL.path)
                }
                .padding(14)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
            } else {
                AppIconForgeEmptyPreview()
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AppIconForgeBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.067, blue: 0.080),
                Color(red: 0.035, green: 0.043, blue: 0.055)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct AppIconForgeSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.54))
    }
}

private struct AppIconForgeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(display)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
            Slider(value: $value, in: range)
                .tint(.cyan)
        }
    }
}

private struct AppIconForgePreviewTile: View {
    let image: NSImage?
    let size: CGFloat
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: max(18, size * 0.22), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
            .frame(width: size + 42, height: size + 42)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct AppIconForgeResultRow: View {
    let title: String
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 54, alignment: .leading)
            Text(path)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct AppIconForgeEmptyPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.82))
            Text("Generated package paths will appear here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AppIconForgeControlButtonStyle: ButtonStyle {
    var accent: Color = .white.opacity(0.72)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.11 : 0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
    }
}

private struct AppIconForgePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                LinearGradient(colors: [.cyan, Color(red: 0.46, green: 0.86, blue: 0.70)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .shadow(color: .cyan.opacity(0.20), radius: 12, y: 4)
    }
}

private struct AppIconForgeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.72))
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
            }
    }
}
