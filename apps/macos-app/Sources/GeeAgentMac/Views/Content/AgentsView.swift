import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentsView: View {
    @Bindable var store: WorkbenchStore
    @State private var detailProfileID: AgentProfileRecord.ID?
    @State private var errorMessage: AgentsFeedbackMessage?
    @State private var successBanner: AgentsTransientFeedback?
    @State private var successBannerDismissTask: Task<Void, Never>?
    @State private var pendingDeleteProfile: AgentProfileRecord?

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 16, alignment: .top)
    ]

    private var detailProfile: AgentProfileRecord? {
        guard let detailProfileID else { return nil }
        return store.availableAgentProfiles.first(where: { $0.id == detailProfileID })
    }

    var body: some View {
        Group {
            if let detailProfile {
                detailPage(detailProfile)
            } else {
                mainPage
            }
        }
        .navigationTitle("Agents")
        .overlay(alignment: .topTrailing) {
            if let successBanner {
                AgentsTransientFeedbackView(message: successBanner)
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: successBanner?.id)
        .alert(item: $errorMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Delete AgentProfile?",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { if !$0 { pendingDeleteProfile = nil } }
            ),
            presenting: pendingDeleteProfile
        ) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                delete(profile)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: { profile in
            Text("This removes the local profile folder and the installed runtime copy for \(profile.name).")
        }
    }

    private var mainPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricsRow
                    .padding(.horizontal)
                    .padding(.top)

                importNotice
                    .padding(.horizontal)

                if let activeProfile = store.activeAgentProfile {
                    activeProfileBanner(activeProfile)
                        .padding(.horizontal)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.availableAgentProfiles) { profile in
                        AgentProfileListCard(
                            profile: profile,
                            isActive: store.activeAgentProfile?.id == profile.id,
                            viewDetailsAction: { openDetail(profile) },
                            setActiveAction: { store.setActiveAgentProfile(profile) },
                            deleteAction: profile.fileState.canDelete ? { pendingDeleteProfile = profile } : nil
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }

    private func detailPage(_ profile: AgentProfileRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailHeader(profile)
                    .padding(.horizontal)
                    .padding(.top)

                summarySection(profile)
                    .padding(.horizontal)

                skillSourcesSection(profile)
                    .padding(.horizontal)

                fileLocationsSection(profile)
                    .padding(.horizontal)

                if !profile.fileState.visualFiles.isEmpty {
                    fileEntrySection(
                        title: "Visual Files",
                        subtitle: "These assets are copied into GeeAgent's local profile workspace at import time.",
                        files: profile.fileState.visualFiles
                    )
                    .padding(.horizontal)
                }

                if !profile.fileState.supplementalFiles.isEmpty {
                    fileEntrySection(
                        title: "Supplemental Files",
                        subtitle: "Optional files preserved from the imported package.",
                        files: profile.fileState.supplementalFiles
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            WorkbenchMetricTile(
                title: "Profiles",
                value: "\(store.availableAgentProfiles.count)",
                systemImage: "person.2"
            )
            WorkbenchMetricTile(
                title: "Bundled",
                value: "\(store.availableAgentProfiles.filter { $0.source == .firstParty }.count)",
                systemImage: "checkmark.seal"
            )
            WorkbenchMetricTile(
                title: "Active",
                value: store.activeAgentProfile?.name ?? "—",
                systemImage: "person.crop.circle.badge.checkmark"
            )
        }
    }

    private var importNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: chooseAgentPack) {
                    Label(store.isImportingAgentPack ? "Importing…" : "Import Agent Definition…", systemImage: "square.and.arrow.down")
                        .font(.geeBodyMedium(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isImportingAgentPack)

                Spacer(minLength: 0)
            }

            Text("New profiles can only be added by importing a complete folder or `.zip` package. GeeAgent currently supports `Agent Definition v2`, and each package must include at least `agent.json`, `identity-prompt.md`, `soul.md`, `playbook.md`, and visual assets.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("After import, GeeAgent copies the full package into the local profile folder and compiles the layered context into the active agent prompt. To change the persona later, edit the files in that folder and then return here and click Reload.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func activeProfileBanner(_ profile: AgentProfileRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.26, green: 0.53, blue: 0.86),
                                Color(red: 0.14, green: 0.19, blue: 0.34),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: profile.source.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Active Persona")
                        .font(.geeDisplaySemibold(12))
                        .foregroundStyle(.secondary)

                    WorkbenchStatusBadge(title: profile.source.title, systemImage: profile.source.systemImage)
                    WorkbenchStatusBadge(title: profile.appearanceTitle, systemImage: "sparkles.rectangle.stack")
                }

                Text(profile.name)
                    .font(.geeDisplaySemibold(28))

                Text(profile.tagline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(profile.skillsSummary, systemImage: "wand.and.rays")
                    Label(profile.allowedToolsSummary, systemImage: "hammer")
                    Label("v\(profile.version)", systemImage: "shippingbox")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func detailHeader(_ profile: AgentProfileRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    detailProfileID = nil
                } label: {
                    Label("Back to Profiles", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                if store.activeAgentProfile?.id == profile.id {
                    WorkbenchStatusBadge(title: "Active", systemImage: "checkmark.circle.fill")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors(for: profile),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: profile.source.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.geeDisplaySemibold(30))

                    Text(profile.tagline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        WorkbenchStatusBadge(title: profile.source.title, systemImage: profile.source.systemImage)
                        WorkbenchStatusBadge(title: profile.appearanceTitle, systemImage: "photo")
                        WorkbenchStatusBadge(title: "v\(profile.version)", systemImage: "shippingbox")
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if store.activeAgentProfile?.id != profile.id {
                    Button("Set Active") {
                        store.setActiveAgentProfile(profile)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if profile.fileState.canReload {
                    Button("Reload") {
                        reload(profile)
                    }
                    .buttonStyle(.bordered)
                }

                if profile.fileState.workspaceRootPath != nil {
                    Button("Open Folder") {
                        store.openAgentProfileFolder(profile)
                    }
                    .buttonStyle(.bordered)
                }

                if profile.fileState.canDelete {
                    Button("Delete", role: .destructive) {
                        pendingDeleteProfile = profile
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func summarySection(_ profile: AgentProfileRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Summary")
                .font(.headline)

            HStack(spacing: 12) {
                summaryPill(title: "ID", value: profile.id)
                summaryPill(title: "Source", value: profile.source.title)
                summaryPill(title: "Appearance", value: profile.appearanceTitle)
            }

            summaryRow(title: "Skills", value: profile.skillsSummary)
            summaryRow(title: "Allowed Tools", value: profile.allowedToolsSummary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func skillSourcesSection(_ profile: AgentProfileRecord) -> some View {
        let sources = store.skillSources.personaSources(for: profile.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Skill Sources")
                    .font(.headline)

                Spacer()

                Text("Refreshes on Reload")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button(action: { choosePersonaSkillSource(profile) }) {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isAddingPersonaSkillSource)
            }

            if sources.isEmpty {
                Text("No persona-specific skill sources.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sources) { source in
                        skillSourceRow(source) {
                            removePersonaSkillSource(source, from: profile)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func skillSourceRow(
        _ source: SkillSourceRecord,
        removeAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.status == "ready" ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(source.status == "ready" ? Color.green : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(source.skillsSummary)
                        .font(.subheadline.weight(.semibold))
                    Text(source.statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(source.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let error = source.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: removeAction) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove source")
            .disabled(store.isRemovingSkillSource)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        }
    }

    private func fileLocationsSection(_ profile: AgentProfileRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Locations")
                .font(.headline)

            fileLocationRow(
                title: "Profile Folder",
                path: profile.fileState.workspaceRootPath
            ) {
                store.openAgentProfileFolder(profile)
            }

            fileLocationRow(
                title: "agent.json",
                path: profile.fileState.manifestPath,
                action: { store.revealAgentProfilePath(profile.fileState.manifestPath) }
            )

            fileLocationRow(
                title: "identity-prompt.md",
                path: profile.fileState.identityPromptPath,
                action: { store.revealAgentProfilePath(profile.fileState.identityPromptPath) }
            )

            fileLocationRow(
                title: "soul.md",
                path: profile.fileState.soulPath,
                action: { store.revealAgentProfilePath(profile.fileState.soulPath) }
            )

            fileLocationRow(
                title: "playbook.md",
                path: profile.fileState.playbookPath,
                action: { store.revealAgentProfilePath(profile.fileState.playbookPath) }
            )

            fileLocationRow(
                title: "tools.md",
                path: profile.fileState.toolsContextPath,
                action: { store.revealAgentProfilePath(profile.fileState.toolsContextPath) }
            )

            fileLocationRow(
                title: "memory.md",
                path: profile.fileState.memorySeedPath,
                action: { store.revealAgentProfilePath(profile.fileState.memorySeedPath) }
            )

            fileLocationRow(
                title: "heartbeat.md",
                path: profile.fileState.heartbeatPath,
                action: { store.revealAgentProfilePath(profile.fileState.heartbeatPath) }
            )
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func fileEntrySection(
        title: String,
        subtitle: String,
        files: [AgentProfileFileEntryRecord]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(files) { file in
                    fileLocationRow(
                        title: file.title,
                        path: file.path,
                        action: { store.revealAgentProfilePath(file.path) }
                    )
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func fileLocationRow(
        title: String,
        path: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let action, let path, !path.isEmpty {
                    Button("Open", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Text(path ?? "Not available for this profile")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        }
    }

    private func openDetail(_ profile: AgentProfileRecord) {
        store.selectedAgentProfileID = profile.id
        detailProfileID = profile.id
    }

    private func chooseAgentPack() {
        let panel = NSOpenPanel()
        panel.title = "Import Agent Definition"
        panel.message = "Choose a complete Agent Definition v2 folder or a .zip archive."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let packURL = panel.url else { return }
        Task {
            do {
                let importedID = try await store.importAgentPack(from: packURL)
                if let importedID {
                    detailProfileID = importedID
                }
                let importedName = importedID
                    .flatMap { id in store.availableAgentProfiles.first(where: { $0.id == id })?.name }
                    ?? packURL.deletingPathExtension().lastPathComponent
                showSuccessBanner(
                    title: "Agent Definition Imported",
                    message: "\(importedName) is now available in the Agents list."
                )
            } catch {
                errorMessage = AgentsFeedbackMessage(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func choosePersonaSkillSource(_ profile: AgentProfileRecord) {
        let panel = NSOpenPanel()
        panel.title = "Add Persona Skill Source"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        Task {
            do {
                try await store.addPersonaSkillSource(from: sourceURL, to: profile)
                showSuccessBanner(
                    title: "Skill Source Added",
                    message: "\(profile.name) will refresh this source on Reload."
                )
            } catch {
                errorMessage = AgentsFeedbackMessage(
                    title: "Skill Source Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func removePersonaSkillSource(_ source: SkillSourceRecord, from profile: AgentProfileRecord) {
        Task {
            do {
                try await store.removePersonaSkillSource(source, from: profile)
                showSuccessBanner(
                    title: "Skill Source Removed",
                    message: "\(profile.name) no longer uses this source."
                )
            } catch {
                errorMessage = AgentsFeedbackMessage(
                    title: "Remove Skill Source Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func reload(_ profile: AgentProfileRecord) {
        Task {
            do {
                try await store.reloadAgentProfile(profile)
                showSuccessBanner(
                    title: "Profile Reloaded",
                    message: "\(profile.name) was re-read from its local workspace folder."
                )
            } catch {
                errorMessage = AgentsFeedbackMessage(
                    title: "Reload Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete(_ profile: AgentProfileRecord) {
        pendingDeleteProfile = nil
        Task {
            do {
                try await store.deleteAgentProfile(profile)
                if detailProfileID == profile.id {
                    detailProfileID = nil
                }
                showSuccessBanner(
                    title: "Profile Deleted",
                    message: "\(profile.name) and its local workspace have been removed."
                )
            } catch {
                errorMessage = AgentsFeedbackMessage(
                    title: "Delete Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showSuccessBanner(title: String, message: String) {
        successBannerDismissTask?.cancel()
        withAnimation {
            successBanner = AgentsTransientFeedback(title: title, message: message)
        }

        successBannerDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    successBanner = nil
                }
            }
        }
    }

    private func gradientColors(for profile: AgentProfileRecord) -> [Color] {
        switch profile.source {
        case .firstParty:
            [Color(red: 0.24, green: 0.56, blue: 0.84), Color(red: 0.15, green: 0.22, blue: 0.4)]
        case .userCreated:
            [Color(red: 0.66, green: 0.43, blue: 0.27), Color(red: 0.31, green: 0.17, blue: 0.12)]
        case .modulePack:
            [Color(red: 0.33, green: 0.55, blue: 0.43), Color(red: 0.12, green: 0.22, blue: 0.18)]
        }
    }
}

private struct AgentProfileListCard: View {
    var profile: AgentProfileRecord
    var isActive: Bool
    var viewDetailsAction: () -> Void
    var setActiveAction: () -> Void
    var deleteAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: profile.source.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.headline)
                            .lineLimit(1)

                        if isActive {
                            WorkbenchStatusBadge(title: "Active", systemImage: "checkmark.circle.fill")
                        }
                    }

                    Text(profile.tagline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                WorkbenchStatusBadge(title: profile.source.title, systemImage: profile.source.systemImage)
                WorkbenchStatusBadge(title: profile.appearanceTitle, systemImage: "photo")
            }

            VStack(alignment: .leading, spacing: 8) {
                profileFact(label: "Skills", value: profile.skillsSummary)
                profileFact(label: "Tools", value: profile.allowedToolsSummary)
                profileFact(label: "Version", value: "v\(profile.version)")
            }

            HStack(spacing: 10) {
                Button("View Details", action: viewDetailsAction)
                    .buttonStyle(.borderedProminent)

                Button(isActive ? "Active" : "Set Active", action: setActiveAction)
                    .buttonStyle(.bordered)
                    .disabled(isActive)

                Spacer(minLength: 0)

                if let deleteAction {
                    Button("Delete", role: .destructive, action: deleteAction)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .background(
                    .regularMaterial.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var gradientColors: [Color] {
        switch profile.source {
        case .firstParty:
            [Color(red: 0.24, green: 0.56, blue: 0.84), Color(red: 0.15, green: 0.22, blue: 0.4)]
        case .userCreated:
            [Color(red: 0.66, green: 0.43, blue: 0.27), Color(red: 0.31, green: 0.17, blue: 0.12)]
        case .modulePack:
            [Color(red: 0.33, green: 0.55, blue: 0.43), Color(red: 0.12, green: 0.22, blue: 0.18)]
        }
    }

    private func profileFact(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct AgentsFeedbackMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

private struct AgentsTransientFeedback: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
}

private struct AgentsTransientFeedbackView: View {
    let message: AgentsTransientFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.66, blue: 0.49),
                                Color(red: 0.19, green: 0.42, blue: 0.31),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(message.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}
