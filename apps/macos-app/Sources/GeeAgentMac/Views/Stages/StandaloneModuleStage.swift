import SwiftUI

/// Full-window module shell: no right nav rail, no `FunctionalStageModule` card chrome.
/// ESC and the back pill call `WorkbenchStore.closeStandaloneModule()`.
struct StandaloneModuleStage: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            moduleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(standaloneBackdrop)
        .onExitCommand(perform: store.closeStandaloneModule)
    }

    private var header: some View {
        HStack(alignment: .center) {
            if let module = store.presentedStandaloneModule {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .font(.geeDisplaySemibold(16))
                        .foregroundStyle(.primary)
                    Text("Module · \(module.displayMode.shortLabel)")
                        .font(.geeBody(11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: store.closeStandaloneModule) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Workbench")
                        .font(.geeBodyMedium(12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var moduleContent: some View {
        if let module = store.presentedStandaloneModule {
            if let nativeGear = GearHost.makeNativeGearView(for: module) {
                nativeGear
            } else {
                GenericFullCanvasModuleStubView(module: module)
            }
        } else {
            Text("Module unavailable.")
                .font(.geeBody(13))
                .foregroundStyle(.secondary)
        }
    }

    private var standaloneBackdrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.18))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.82))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.9)
        }
    }
}

// MARK: - Fallback

private struct GenericFullCanvasModuleStubView: View {
    let module: InstalledAppRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(module.summary)
                .font(.geeBody(13))
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
