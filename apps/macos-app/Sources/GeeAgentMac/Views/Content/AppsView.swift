import SwiftUI

/// Gear catalog: optional atmosphere apps and home widgets.
struct AppsView: View {
    @Bindable var store: WorkbenchStore

    @Environment(\.openWindow) private var openWindow
    @State private var selectedKind: GearKind = .atmosphere
    @State private var preparationSnapshots: [String: GearPreparationSnapshot] = [:]

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 68, 320), 1120)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    gearList(width: contentWidth)
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 44)
                .frame(maxWidth: contentWidth, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Gears")
                .font(.geeDisplaySemibold(34))
                .foregroundStyle(.white.opacity(0.95))

            GearKindSegmentedControl(selection: $selectedKind)
        }
    }

    private func gearList(width: CGFloat) -> some View {
        LazyVGrid(columns: gearGridColumns(for: width), alignment: .leading, spacing: 14) {
            ForEach(filteredApps) { app in
                GearCatalogCard(
                    app: app,
                    preparation: preparationSnapshots[app.id],
                    openAction: {
                        Task {
                            await prepareAndOpenGear(app)
                        }
                    }
                )
            }

            if filteredApps.isEmpty {
                GearEmptyState(kind: selectedKind)
                    .gridCellColumns(gearGridColumns(for: width).count)
            }
        }
    }

    private func gearGridColumns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 14
        let targetWidth: CGFloat = 336
        let count = min(3, max(1, Int((width + spacing) / (targetWidth + spacing))))
        return Array(
            repeating: GridItem(.flexible(minimum: 260, maximum: 380), spacing: spacing, alignment: .top),
            count: count
        )
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
        guard app.installState == .installed else {
            return
        }
        GearHost.setEnabled(true, gearID: app.id)

        guard let manifest = GearHost.manifest(gearID: app.id) else {
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

        if let windowID = GearHost.dedicatedWindowID(gearID: app.id) {
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
        HStack(spacing: 6) {
            ForEach(GearKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        selection = kind
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(kind.catalogTabTitle)
                            .font(.geeDisplaySemibold(12))
                    }
                    .foregroundStyle(selection == kind ? .white.opacity(0.96) : .white.opacity(0.58))
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selection == kind ? Color.white.opacity(0.17) : Color.white.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(selection == kind ? 0.18 : 0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GearCatalogCard: View {
    let app: InstalledAppRecord
    let preparation: GearPreparationSnapshot?
    var openAction: () -> Void

    private var canOpen: Bool {
        app.installState == .installed
            && preparation?.state.isBusy != true
            && preparation?.state != .unsupported
    }

    private var attentionStateTitle: String? {
        guard app.installState == .installed else {
            return app.installState == .installError ? "Issue detected" : app.installState.title
        }
        guard let preparation, preparation.state != .ready, preparation.state != .unknown else {
            return nil
        }
        switch preparation.state {
        case .checking:
            return "Checking"
        case .needsSetup:
            return "Setup required"
        case .installing:
            return "Installing"
        case .installFailed:
            return "Install failed"
        case .unsupported:
            return "Unsupported"
        case .unknown, .ready:
            return nil
        }
    }

    private var attentionStateImage: String {
        if app.installState == .installed, let preparation, preparation.state != .ready {
            return preparation.state.systemImage
        }
        return app.installState.systemImage
    }

    private var attentionStateColor: Color {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                cover

                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(.geeDisplaySemibold(16))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    Text("by \(app.developerLabel.isEmpty ? "Unknown" : app.developerLabel)")
                        .font(.geeBodyMedium(12))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Text(effectiveSummary)
                .font(.geeBody(12))
                .foregroundStyle(summaryColor)
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)

            HStack(alignment: .center, spacing: 7) {
                sharpTag(app.gearKind.catalogTabTitle)
                sharpTag(app.versionLabel)
                if let attentionStateTitle {
                    attentionPill(title: attentionStateTitle)
                }

                Spacer(minLength: 8)

                openButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        .padding(13)
        .background(.ultraThinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.13))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
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
        .frame(width: 78, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func attentionPill(title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: attentionStateImage)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.geeDisplaySemibold(10))
        }
        .foregroundStyle(attentionStateColor)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(attentionStateColor.opacity(0.12))
        )
    }

    private var openButton: some View {
        Button {
            openAction()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: app.gearKind == .widget ? "house" : "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                Text(openButtonTitle)
                    .font(.geeDisplaySemibold(11))
            }
            .foregroundStyle(canOpen ? .black.opacity(0.82) : .white.opacity(0.34))
            .frame(width: 72, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(canOpen ? Color.white.opacity(0.86) : Color.white.opacity(0.055))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }

    private func sharpTag(_ text: String) -> some View {
        Text(text)
            .font(.geeBodyMedium(10))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
            }
    }

    private var cardBorderColor: Color {
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
            Text("Drop a valid gear folder into the Gears directory and restart GeeAgent to reveal it here.")
                .font(.geeBody(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassCard(cornerRadius: 12, darken: 0.1, materialOpacity: 0.46)
    }
}

private extension GearKind {
    var catalogTabTitle: String {
        switch self {
        case .atmosphere:
            "App"
        case .widget:
            "Widget"
        }
    }
}
