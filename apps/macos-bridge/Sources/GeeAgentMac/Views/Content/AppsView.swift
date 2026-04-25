import SwiftUI

/// Gear catalog: optional atmosphere apps and home widgets.
struct AppsView: View {
    @Bindable var store: WorkbenchStore

    @Environment(\.openWindow) private var openWindow
    @State private var selectedKind: GearKind = .atmosphere
    @State private var appEnablementRevision = 0
    @State private var preparationSnapshots: [String: GearPreparationSnapshot] = [:]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    gearList
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 44)
                .frame(maxWidth: min(proxy.size.width - 68, 1120), alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .navigationTitle("Gears")
        .task {
            await loadCachedPreparationSnapshots()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text("Gears")
                    .font(.geeDisplaySemibold(34))
                    .foregroundStyle(.white.opacity(0.95))

                Text("optional native accessories")
                    .font(.geeBodyMedium(13))
                    .foregroundStyle(.white.opacity(0.46))
            }

            GearKindSegmentedControl(selection: $selectedKind)

            Text(selectedKind.subtitle)
                .font(.geeBody(13))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
        }
    }

    private var gearList: some View {
        LazyVStack(spacing: 14) {
            ForEach(filteredApps) { app in
                GearCatalogRow(
                    app: app,
                    isOptionalAccessory: GearRegistry.isOptionalAccessory(gearID: app.id),
                    isEnabled: isAppEnabled(app),
                    preparation: preparationSnapshots[app.id],
                    setEnabled: { isEnabled in
                        GearRegistry.setEnabled(isEnabled, gearID: app.id)
                        appEnablementRevision += 1
                    },
                    openAction: {
                        Task {
                            await prepareAndOpenGear(app)
                        }
                    }
                )
            }

            if filteredApps.isEmpty {
                GearEmptyState(kind: selectedKind)
            }
        }
    }

    private var filteredApps: [InstalledAppRecord] {
        catalogApps
            .filter { $0.gearKind == selectedKind }
            .sorted { lhs, rhs in
                if lhs.installState != rhs.installState {
                    return lhs.installState == .installed
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var catalogApps: [InstalledAppRecord] {
        store.installedApps.filter(\.isGearPackage)
    }

    private func prepareAndOpenGear(_ app: InstalledAppRecord) async {
        guard app.installState == .installed, isAppEnabled(app) else {
            return
        }

        guard let manifest = GearRegistry.manifest(gearID: app.id) else {
            openPreparedGear(app)
            return
        }

        preparationSnapshots[app.id] = GearPreparationSnapshot(
            gearID: app.id,
            state: .checking,
            summary: "Checking dependencies...",
            detail: nil,
            missingDependencyIDs: [],
            updatedAt: Date()
        )

        let snapshot = await GearPreparationService.shared.prepareIfNeeded(manifest: manifest) { snapshot in
            await MainActor.run {
                preparationSnapshots[app.id] = snapshot
            }
        }
        preparationSnapshots[app.id] = snapshot
        guard snapshot.state == .ready else {
            return
        }

        openPreparedGear(app)
    }

    private func openPreparedGear(_ app: InstalledAppRecord) {
        if app.gearKind == .widget {
            store.openSection(.home)
            return
        }

        if let windowID = GearRegistry.dedicatedWindowID(gearID: app.id) {
            openWindow(id: windowID)
            return
        }

        switch app.displayMode {
        case .fullCanvas:
            store.openStandaloneModule(id: app.id)
        case .inNav:
            store.selectedExtension = .app(app.id)
        }
    }

    private func isAppEnabled(_ app: InstalledAppRecord) -> Bool {
        _ = appEnablementRevision
        return GearRegistry.isEnabled(gearID: app.id)
    }

    private func loadCachedPreparationSnapshots() async {
        var snapshots: [String: GearPreparationSnapshot] = [:]
        for app in catalogApps where app.installState == .installed {
            if let snapshot = await GearPreparationService.shared.cachedSnapshot(for: app.id) {
                snapshots[app.id] = snapshot
            }
        }
        preparationSnapshots = snapshots
    }
}

private struct GearKindSegmentedControl: View {
    @Binding var selection: GearKind

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GearKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        selection = kind
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(kind.title)
                            .font(.geeDisplaySemibold(13))
                    }
                    .foregroundStyle(selection == kind ? .white.opacity(0.96) : .white.opacity(0.58))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selection == kind ? Color.white.opacity(0.17) : Color.white.opacity(0.06))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(selection == kind ? 0.18 : 0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GearCatalogRow: View {
    let app: InstalledAppRecord
    let isOptionalAccessory: Bool
    let isEnabled: Bool
    let preparation: GearPreparationSnapshot?
    var setEnabled: (Bool) -> Void
    var openAction: () -> Void

    private var canOpen: Bool {
        app.installState == .installed
            && isEnabled
            && preparation?.state.isBusy != true
            && preparation?.state != .unsupported
    }

    private var effectiveStateTitle: String {
        guard app.installState == .installed else {
            return app.installState == .installError ? "Issue detected" : app.installState.title
        }
        guard let preparation, preparation.state != .ready else {
            return "Installed"
        }
        return switch preparation.state {
        case .checking: "Checking"
        case .needsSetup: "Setup required"
        case .installing: "Installing"
        case .installFailed: "Install failed"
        case .unsupported: "Unsupported"
        case .unknown: "Unknown"
        case .ready: "Installed"
        }
    }

    private var effectiveStateImage: String {
        if app.installState == .installed, let preparation, preparation.state != .ready {
            return preparation.state.systemImage
        }
        return app.installState.systemImage
    }

    private var effectiveStateColor: Color {
        guard app.installState == .installed else {
            return app.installState == .installError ? .orange.opacity(0.95) : .green.opacity(0.92)
        }
        guard let preparation else {
            return .green.opacity(0.92)
        }
        switch preparation.state {
        case .ready:
            return .green.opacity(0.92)
        case .checking, .installing:
            return .blue.opacity(0.92)
        case .needsSetup:
            return .yellow.opacity(0.92)
        case .installFailed, .unsupported:
            return .orange.opacity(0.95)
        case .unknown:
            return .white.opacity(0.62)
        }
    }

    private var openButtonTitle: String {
        guard app.installState == .installed else {
            return "Blocked"
        }
        guard let preparation, preparation.state != .ready else {
            return app.gearKind == .widget ? "Home" : "Open"
        }
        return switch preparation.state {
        case .checking: "Checking"
        case .needsSetup: "Install"
        case .installing: "Installing"
        case .installFailed: "Retry"
        case .unsupported: "Blocked"
        case .unknown: "Open"
        case .ready: app.gearKind == .widget ? "Home" : "Open"
        }
    }

    private var effectiveSummary: String {
        guard app.installState == .installed else {
            return app.installIssue ?? app.summary
        }
        return preparation?.summary ?? app.summary
    }

    private var summaryColor: Color {
        app.installState == .installError || preparation?.state == .installFailed
            ? .orange.opacity(0.9)
            : .white.opacity(0.62)
    }

    var body: some View {
        HStack(spacing: 18) {
            cover

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Text(app.name)
                        .font(.geeDisplaySemibold(18))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    installPill
                }

                Text("by \(app.developerLabel.isEmpty ? "Unknown" : app.developerLabel)")
                    .font(.geeBodyMedium(12))
                    .foregroundStyle(.white.opacity(0.42))

                Text(effectiveSummary)
                    .font(.geeBody(13))
                    .foregroundStyle(summaryColor)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    capsuleText(app.categoryLabel)
                    capsuleText(app.versionLabel)
                    if app.gearKind == .widget {
                        capsuleText("Home Widget")
                    }
                }
            }

            Spacer(minLength: 12)

            controls
        }
        .padding(14)
        .background(.ultraThinMaterial.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.13))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
    }

    @ViewBuilder
    private var cover: some View {
        ZStack {
            if let coverURL = app.coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 124, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        }
    }

    private var placeholderCover: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.75, blue: 0.58).opacity(0.45),
                    Color(red: 0.12, green: 0.27, blue: 0.96).opacity(0.34),
                    Color.black.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: app.gearKind.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var installPill: some View {
        HStack(spacing: 5) {
            Image(systemName: effectiveStateImage)
                .font(.system(size: 10, weight: .bold))
            Text(effectiveStateTitle)
                .font(.geeDisplaySemibold(10))
        }
        .foregroundStyle(effectiveStateColor)
        .padding(.horizontal, 8)
        .frame(height: 21)
        .background(
            Capsule(style: .continuous)
                .fill(effectiveStateColor.opacity(0.12))
        )
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isOptionalAccessory && app.installState == .installed {
                Button {
                    setEnabled(!isEnabled)
                } label: {
                    Text(isEnabled ? "Enabled" : "Disabled")
                        .font(.geeDisplaySemibold(11))
                        .foregroundStyle(isEnabled ? .white.opacity(0.9) : .white.opacity(0.42))
                        .frame(width: 82, height: 30)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isEnabled ? Color.green.opacity(0.18) : Color.white.opacity(0.06))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
            }

            Button {
                openAction()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: app.gearKind == .widget ? "house" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(openButtonTitle)
                        .font(.geeDisplaySemibold(11))
                }
                .foregroundStyle(canOpen ? .black.opacity(0.82) : .white.opacity(0.34))
                .frame(width: 82, height: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(canOpen ? Color.white.opacity(0.86) : Color.white.opacity(0.055))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
        }
    }

    private func capsuleText(_ text: String) -> some View {
        Text(text)
            .font(.geeBodyMedium(11))
            .foregroundStyle(.white.opacity(0.46))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.white.opacity(0.06), in: Capsule(style: .continuous))
    }

    private var rowBorderColor: Color {
        app.installState == .installError || preparation?.state == .installFailed ? .orange.opacity(0.32) : .white.opacity(0.13)
    }
}

private struct GearEmptyState: View {
    let kind: GearKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            Text("No \(kind.title) yet")
                .font(.geeDisplaySemibold(18))
                .foregroundStyle(.white.opacity(0.86))
            Text("Drop a valid gear folder into the gears directory and restart GeeAgent to reveal it here.")
                .font(.geeBody(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassCard(cornerRadius: 22, darken: 0.1, materialOpacity: 0.46)
    }
}
