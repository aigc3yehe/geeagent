import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct MediaGeneratorGearModuleView: View {
    var body: some View {
        MediaGeneratorGearRootView()
    }
}

struct MediaGeneratorGearWindow: View {
    var body: some View {
        MediaGeneratorGearRootView()
            .frame(minWidth: 1040, minHeight: 700)
    }
}

private struct MediaGeneratorGearRootView: View {
    @StateObject private var store = MediaGeneratorGearStore.shared
    @State private var pastedReferenceURL = ""
    @State private var isReferenceDropzoneHovered = false
    @State private var previewTask: MediaGeneratorTask?
    @State private var previewReference: MediaGeneratorReference?
    @State private var unmutedVideoTaskIDs: Set<MediaGeneratorTask.ID> = []
    @State private var isQuickPromptEditorPresented = false
    @State private var isImageHistoryPresented = false

    var body: some View {
        ZStack {
            MediaGeneratorBackdrop()
            HStack(spacing: 0) {
                leftPanel
                Rectangle()
                    .fill(MediaGeneratorPalette.border)
                    .frame(width: 1)
                rightPanel
            }
            if let previewTask {
                MediaGeneratorPreviewOverlay(
                    task: previewTask,
                    isVideoMuted: isVideoMuted(previewTask),
                    onToggleVideoMute: {
                        toggleVideoMute(previewTask)
                    },
                    onClose: {
                        self.previewTask = nil
                    },
                    onDownload: {
                        store.downloadResult(previewTask)
                    }
                )
                .transition(.opacity)
            }
            if let previewReference, let previewURL = previewReference.previewURL {
                MediaGeneratorReferencePreviewOverlay(
                    reference: previewReference,
                    url: previewURL,
                    onClose: {
                        self.previewReference = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.16), value: previewTask?.id)
        .animation(.easeOut(duration: 0.16), value: previewReference?.id)
        .background(MediaGeneratorThinScrollbars())
        .background(
            MediaGeneratorReferencePasteMonitor(
                isEnabled: store.category == .image || store.category == .video,
                onPasteImage: {
                    store.addClipboardReferenceImage()
                }
            )
        )
        .sheet(isPresented: $isQuickPromptEditorPresented) {
            MediaGeneratorQuickPromptEditor(store: store)
        }
        .sheet(isPresented: $isImageHistoryPresented) {
            MediaGeneratorImageHistorySheet(store: store)
        }
    }

    private func isVideoMuted(_ task: MediaGeneratorTask) -> Bool {
        task.category != .video || !unmutedVideoTaskIDs.contains(task.id)
    }

    private func toggleVideoMute(_ task: MediaGeneratorTask) {
        guard task.category == .video else {
            return
        }
        if unmutedVideoTaskIDs.contains(task.id) {
            unmutedVideoTaskIDs.remove(task.id)
        } else {
            unmutedVideoTaskIDs.insert(task.id)
        }
    }

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                categorySwitcher

                if store.category == .image || store.category == .video {
                    mediaModelControls
                    promptStudioSection
                    referencesPanel
                    generateFooter
                } else {
                    placeholderControls
                }

                HStack(spacing: 9) {
                    Image(systemName: store.isBusy ? "clock" : "checkmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.isBusy ? .orange : .green)
                    Text(store.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
        .frame(width: 380)
        .background(.white.opacity(0.01))
    }

    private var categorySwitcher: some View {
        HStack(spacing: 2) {
            ForEach(MediaGeneratorCategory.allCases) { category in
                Button {
                    store.selectCategory(category)
                } label: {
                    Label(localizedCategoryTitle(category), systemImage: category.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MediaGeneratorSegmentButtonStyle(isActive: store.category == category))
            }
        }
        .padding(3)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 0.8)
        }
    }

    private var mediaModelControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                MediaGeneratorReadonlyField(title: "Provider", value: "Xenodia")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                    Menu {
                        ForEach(MediaGeneratorGearStore.availableModels(for: store.category)) { model in
                            Button(model.title) {
                                store.selectModel(model)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(store.selectedModel.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .buttonStyle(MediaGeneratorSelectButtonStyle())
                }
            }

            generationParameterControls
        }
    }

    private var generationParameterControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            MediaGeneratorSectionTitle("Parameters")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                MediaGeneratorOptionField(
                    title: "Aspect",
                    selection: aspectRatioBinding,
                    options: MediaGeneratorGearStore.supportedAspectRatios(for: store.selectedModel)
                )
                MediaGeneratorOptionField(
                    title: "Resolution",
                    selection: resolutionBinding,
                    options: MediaGeneratorGearStore.supportedResolutions(for: store.selectedModel, aspectRatio: store.aspectRatio)
                )
                if store.category == .image, store.selectedModel == .nanoBananaPro {
                    MediaGeneratorOptionField(
                        title: "Format",
                        selection: $store.outputFormat,
                        options: MediaGeneratorOutputFormat.allCases
                    )
                }
                if store.category == .image || store.category == .video {
                    MediaGeneratorMediaCountField(
                        title: store.category == .video ? "Videos" : "Images",
                        selection: $store.imageCount
                    )
                }
                if store.category == .video {
                    MediaGeneratorVideoModeField(
                        selection: videoGenerationTypeBinding,
                        options: MediaGeneratorGearStore.supportedVideoGenerationTypes(for: store.selectedModel)
                    )
                    if store.selectedModel.isSeedance {
                        MediaGeneratorVideoDurationField(selection: $store.videoDuration)
                    }
                }
            }
            if store.category == .image {
                MediaGeneratorCheckboxRow(
                    title: "Async task",
                    helpText: "When enabled, Gee asks Xenodia to create a background task and polls until the generated image is ready. When disabled, Gee asks Xenodia for a synchronous response; if the provider supports it, the result can return directly, but long generations are more likely to hit request timeouts.",
                    isOn: $store.useAsync
                )
            }
            if store.selectedModel.isSeedance {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    MediaGeneratorCheckboxRow(
                        title: "Audio",
                        helpText: "Ask Seedance to generate audio together with the video when the selected model and prompt support it.",
                        isOn: $store.generateAudio
                    )
                    MediaGeneratorCheckboxRow(
                        title: "Web Search",
                        helpText: "Allow Seedance to use provider-side web grounding for prompts that benefit from current external context.",
                        isOn: $store.webSearch
                    )
                    MediaGeneratorCheckboxRow(
                        title: "NSFW Check",
                        helpText: "Enable provider-side safety screening for the generated video output.",
                        isOn: $store.nsfwChecker
                    )
                }
            }
        }
    }

    private var placeholderControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaGeneratorSectionTitle("\(store.category.title) Channel")
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(MediaGeneratorPalette.accent)
                Text("Reserved for Xenodia")
                    .font(.headline)
                Text("We are not connecting Kie, Tuzi, or other providers from the reference project. This tab will activate when the global Xenodia channel exposes \(store.category.rawValue) generation endpoints.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    private var promptStudioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MediaGeneratorSectionTitle("Prompt & Parameters")
                Spacer()
                Button {
                    isQuickPromptEditorPresented = true
                } label: {
                    Label("Prompts", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(MediaGeneratorGhostButtonStyle())
                Button {
                    store.prompt = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(MediaGeneratorGhostButtonStyle(role: .destructive))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.prompt)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 0.8)
                }
                if store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe what you want to generate...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 200)

            HStack(spacing: 6) {
                Button {
                    isQuickPromptEditorPresented = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(MediaGeneratorQuickPromptIconButtonStyle())
                ForEach(store.quickPrompts) { quickPrompt in
                    MediaGeneratorQuickPromptButton(title: quickPrompt.name) {
                        appendPromptLine(quickPrompt.content)
                    }
                }
            }
        }
    }

    private var generateFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.generateCurrentPrompt()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text("Generate Now")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MediaGeneratorPrimaryButtonStyle())
            .disabled(store.category == .audio || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func appendPromptLine(_ line: String) {
        let trimmedPrompt = store.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        store.prompt = trimmedPrompt.isEmpty ? line : "\(store.prompt)\n\(line)"
    }

    private func localizedCategoryTitle(_ category: MediaGeneratorCategory) -> String {
        switch category {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        }
    }

    private var aspectRatioBinding: Binding<MediaGeneratorAspectRatio> {
        Binding(
            get: { store.aspectRatio },
            set: { value in
                store.aspectRatio = value
                store.normalizeSelectionForCurrentModel()
            }
        )
    }

    private var resolutionBinding: Binding<MediaGeneratorResolution> {
        Binding(
            get: { store.resolution },
            set: { value in
                store.resolution = value
                store.normalizeSelectionForCurrentModel()
            }
        )
    }

    private var videoGenerationTypeBinding: Binding<MediaGeneratorVideoGenerationType> {
        Binding(
            get: { store.videoGenerationType },
            set: { value in
                store.videoGenerationType = value
                store.normalizeSelectionForCurrentModel()
            }
        )
    }

    private var referencesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reference Images")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                Text("\(store.references.count)/\(store.selectedModelReferenceLimit)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MediaGeneratorPalette.accent)
                Spacer()
                Button {
                    store.addClipboardReferenceImage()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
                Button {
                    isImageHistoryPresented = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
            }

            HStack(spacing: 8) {
                TextField(store.category == .video ? "Paste image URL or asset://" : "Paste image URL", text: $pastedReferenceURL)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 0.8)
                    }
                Button("Add URL") {
                    store.addReferenceURL(pastedReferenceURL)
                    pastedReferenceURL = ""
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
            }

            Button {
                store.addReferenceFiles()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: isReferenceDropzoneHovered ? "photo.badge.plus.fill" : "photo.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                    Text("Click or drag reference images")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(isReferenceDropzoneHovered ? .white : .white.opacity(0.62))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isReferenceDropzoneHovered ? MediaGeneratorPalette.accent.opacity(0.08) : Color.white.opacity(0.025))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isReferenceDropzoneHovered ? MediaGeneratorPalette.accent.opacity(0.65) : MediaGeneratorPalette.border,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
            }
            .buttonStyle(.plain)
            .onHover { isReferenceDropzoneHovered = $0 }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else {
                    return false
                }
                for url in urls {
                    store.addReferenceFileURL(url)
                }
                return true
            } isTargeted: { isTargeted in
                isReferenceDropzoneHovered = isTargeted
            }

            if !store.references.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 7), count: 5), alignment: .leading, spacing: 7) {
                    ForEach(store.references) { reference in
                        MediaGeneratorReferenceThumb(
                            reference: reference,
                            onPreview: {
                                previewReference = reference
                            },
                            onRemove: {
                                store.removeReference(reference)
                                if previewReference?.id == reference.id {
                                    previewReference = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Task List")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                    Text("\(store.visibleTaskGroups.count)/\(store.taskGroups.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
                MediaGeneratorSearchField(text: $store.searchQuery)
                    .frame(width: 220)
                Menu {
                    ForEach(MediaGeneratorTaskFilter.allCases) { filter in
                        Button(filter.title) {
                            store.taskFilter = filter
                        }
                    }
                } label: {
                    Label(store.taskFilter.title, systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(MediaGeneratorFilterItemButtonStyle())
                Menu {
                    Button("All models") {
                        store.modelFilter = nil
                    }
                    ForEach(MediaGeneratorModelID.allCases) { model in
                        Button(model.title) {
                            store.modelFilter = model
                        }
                    }
                } label: {
                    Label(store.modelFilter?.title ?? "All models", systemImage: "rectangle.stack")
                }
                .buttonStyle(MediaGeneratorFilterItemButtonStyle())
                Button {
                    store.loadTasks()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(MediaGeneratorClearCacheButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.white.opacity(0.02))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MediaGeneratorPalette.border)
                    .frame(height: 1)
            }

            ScrollView {
                if store.visibleTaskGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "display")
                            .font(.system(size: 30, weight: .medium))
                        Text(store.tasks.isEmpty ? "No generation tasks yet" : "No matching tasks")
                            .font(.subheadline.weight(.semibold))
                        Text(store.tasks.isEmpty ? "Generated images, videos, and async status will appear here." : "Try another status, model, or search keyword.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.44))
                    }
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 220)
                    .padding(.horizontal, 24)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.visibleTaskGroups) { group in
                            if group.isBatch {
                                MediaGeneratorTaskGroupCard(
                                    group: group,
                                    isSelected: group.tasks.contains { $0.id == store.selectedTaskID },
                                    isVideoMuted: { task in
                                        isVideoMuted(task)
                                    },
                                    onPreview: { task in
                                        previewTask = task
                                    },
                                    onToggleVideoMute: { task in
                                        toggleVideoMute(task)
                                    },
                                    onDownload: { task in
                                        store.downloadResult(task)
                                    },
                                    onCopy: { task in
                                        store.copyResultURL(task)
                                    },
                                    onReveal: { task in
                                        store.revealResultInFinder(task)
                                    },
                                    onUseAsReference: { task in
                                        store.useResultAsReference(task)
                                    },
                                    onApply: {
                                        store.applyTaskParameters(group.representative)
                                    },
                                    onStar: {
                                        store.toggleStar(group)
                                    },
                                    onDelete: {
                                        store.delete(group)
                                    }
                                ) {
                                    store.selectedTaskID = group.representative.id
                                }
                            } else {
                                let task = group.representative
                                MediaGeneratorTaskCard(
                                    task: task,
                                    isSelected: store.selectedTaskID == task.id,
                                    isVideoMuted: isVideoMuted(task),
                                    onPreview: {
                                        previewTask = task
                                    },
                                    onToggleVideoMute: {
                                        toggleVideoMute(task)
                                    },
                                    onDownload: {
                                        store.downloadResult(task)
                                    },
                                    onCopy: {
                                        store.copyResultURL(task)
                                    },
                                    onReveal: {
                                        store.revealResultInFinder(task)
                                    },
                                    onUseAsReference: {
                                        store.useResultAsReference(task)
                                    },
                                    onApply: {
                                        store.applyTaskParameters(task)
                                    },
                                    onStar: {
                                        store.toggleStar(task)
                                    },
                                    onDelete: {
                                        store.delete(task)
                                    }
                                ) {
                                    store.selectedTaskID = task.id
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.10))
    }
}

private struct MediaGeneratorReadonlyField: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
                .padding(.horizontal, 10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MediaGeneratorPalette.border, lineWidth: 1)
                }
        }
    }
}

private struct MediaGeneratorOptionField<Value: Identifiable & RawRepresentable & Hashable>: View where Value.RawValue == String {
    var title: String
    @Binding var selection: Value
    var options: [Value]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Menu {
                ForEach(options, id: \.rawValue) { value in
                    Button(value.rawValue) {
                        selection = value
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .buttonStyle(MediaGeneratorSelectButtonStyle())
        }
    }
}

private struct MediaGeneratorMediaCountField: View {
    var title: String
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Menu {
                ForEach(1...4, id: \.self) { count in
                    Button("\(count)") {
                        selection = count
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(selection)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .buttonStyle(MediaGeneratorSelectButtonStyle())
        }
    }
}

private struct MediaGeneratorVideoModeField: View {
    @Binding var selection: MediaGeneratorVideoGenerationType
    var options: [MediaGeneratorVideoGenerationType]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Menu {
                ForEach(options) { mode in
                    Button(mode.title) {
                        selection = mode
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .buttonStyle(MediaGeneratorSelectButtonStyle())
        }
    }
}

private struct MediaGeneratorVideoDurationField: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seconds")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Menu {
                ForEach(4...15, id: \.self) { seconds in
                    Button("\(seconds)") {
                        selection = seconds
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(selection)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .buttonStyle(MediaGeneratorSelectButtonStyle())
        }
    }
}

private struct MediaGeneratorCheckboxRow: View {
    var title: String
    var helpText: String?
    @Binding var isOn: Bool
    @State private var isHelpPresented = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? MediaGeneratorPalette.success : .white.opacity(0.58))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if helpText != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            guard helpText != nil else { return }
            isHelpPresented = isHovering
        }
        .popover(isPresented: $isHelpPresented, arrowEdge: .trailing) {
            if let helpText {
                Text(helpText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(width: 280, alignment: .leading)
            }
        }
    }
}

private struct MediaGeneratorSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
            TextField("Search prompt, URL, status...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MediaGeneratorPalette.border, lineWidth: 1)
        }
    }
}

private struct MediaGeneratorTaskTinyBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MediaGeneratorQuickPromptEditor: View {
    @ObservedObject var store: MediaGeneratorGearStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPromptID: MediaGeneratorQuickPrompt.ID?
    @State private var name = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Prompts")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Create reusable prompt snippets for the left prompt studio.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
            }

            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.quickPrompts) { prompt in
                            Button {
                                select(prompt)
                            } label: {
                                HStack(spacing: 9) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(prompt.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.88))
                                        Text(prompt.content)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.42))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selectedPromptID == prompt.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(MediaGeneratorPalette.accentLight)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(selectedPromptID == prompt.id ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selectedPromptID == prompt.id ? MediaGeneratorPalette.accent.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(width: 220)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MediaGeneratorPalette.border, lineWidth: 1)
                        }

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $content)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
                            }
                        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Prompt snippet")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.26))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 150)

                    HStack(spacing: 8) {
                        Button(selectedPromptID == nil ? "Add Prompt" : "Save Changes") {
                            save()
                        }
                        .buttonStyle(MediaGeneratorPrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("New") {
                            clearForm()
                        }
                        .buttonStyle(MediaGeneratorPillButtonStyle())

                        if let selectedPrompt {
                            Button("Delete") {
                                store.deleteQuickPrompt(selectedPrompt)
                                clearForm()
                            }
                            .buttonStyle(MediaGeneratorGhostButtonStyle(role: .destructive))
                        }
                    }

                    Button("Reset to Defaults") {
                        store.resetQuickPrompts()
                        clearForm()
                    }
                    .buttonStyle(MediaGeneratorPillButtonStyle())
                }
            }
        }
        .padding(18)
        .frame(width: 650, height: 430)
        .foregroundStyle(.white)
        .background(MediaGeneratorPalette.background)
        .background(MediaGeneratorThinScrollbars())
        .onAppear {
            if selectedPromptID == nil, let first = store.quickPrompts.first {
                select(first)
            }
        }
    }

    private var selectedPrompt: MediaGeneratorQuickPrompt? {
        store.quickPrompts.first { $0.id == selectedPromptID }
    }

    private func select(_ prompt: MediaGeneratorQuickPrompt) {
        selectedPromptID = prompt.id
        name = prompt.name
        content = prompt.content
    }

    private func clearForm() {
        selectedPromptID = nil
        name = ""
        content = ""
    }

    private func save() {
        if let selectedPrompt {
            store.updateQuickPrompt(selectedPrompt, name: name, content: content)
        } else {
            store.addQuickPrompt(name: name, content: content)
            if let created = store.quickPrompts.last {
                select(created)
            }
        }
    }
}

private struct MediaGeneratorImageHistorySheet: View {
    @ObservedObject var store: MediaGeneratorGearStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reference History")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Recent reference images from pasted links, clipboard, and local files.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
            }

            if store.imageHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 30, weight: .medium))
                    Text("No reference images yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Pasted URLs, clipboard images, and local reference files will appear here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.44))
                }
                .foregroundStyle(.white.opacity(0.50))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.imageHistory) { item in
                            MediaGeneratorImageHistoryTile(
                                item: item,
                                onApply: {
                                    store.applyImageHistory(item)
                                    dismiss()
                                },
                                onDelete: {
                                    store.removeImageHistory(item)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 760, height: 520)
        .foregroundStyle(.white)
        .background(MediaGeneratorPalette.background)
        .background(MediaGeneratorThinScrollbars())
    }
}

private struct MediaGeneratorImageHistoryTile: View {
    var item: MediaGeneratorImageHistoryItem
    var onApply: () -> Void
    var onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                preview
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(hostText)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
            }

            Text(detailText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)

            HStack(spacing: 6) {
                Button("Use") {
                    onApply()
                }
                .buttonStyle(MediaGeneratorPillButtonStyle())
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: .red))
            }
        }
        .padding(9)
        .background(.white.opacity(isHovered ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? MediaGeneratorPalette.accent.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let url = item.previewURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle()
                        .fill(.white.opacity(0.055))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.white.opacity(0.32))
                        }
                }
            }
        } else {
            Rectangle().fill(.white.opacity(0.055))
        }
    }

    private var hostText: String {
        if let url = item.url {
            return URL(string: url)?.host ?? "Image Link"
        }
        return "Local File"
    }

    private var detailText: String {
        if let url = item.url {
            return url
        }
        return item.localPath ?? item.displayName
    }
}

private struct MediaGeneratorPicker<Value: CaseIterable & Identifiable & RawRepresentable & Hashable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    var title: String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
            Spacer()
            HStack(spacing: 6) {
                Picker(title, selection: $selection) {
                    ForEach(Array(Value.allCases), id: \.rawValue) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 118)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.8)
            }
        }
    }
}

private struct MediaGeneratorOptionPicker<Value: Identifiable & RawRepresentable & Hashable>: View where Value.RawValue == String {
    var title: String
    @Binding var selection: Value
    var options: [Value]

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
            Spacer()
            HStack(spacing: 6) {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.rawValue) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 118)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.8)
            }
        }
    }
}

private struct MediaGeneratorFixedValueRow: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.56))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(MediaGeneratorPalette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(MediaGeneratorPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 2)
    }
}

private struct MediaGeneratorToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? MediaGeneratorPalette.accent.opacity(0.26) : Color.white.opacity(0.08))
                    Circle()
                        .fill(isOn ? MediaGeneratorPalette.accent : Color.white.opacity(0.55))
                        .frame(width: 15, height: 15)
                        .padding(3)
                }
                .frame(width: 36, height: 21)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

private struct MediaGeneratorReferenceThumb: View {
    var reference: MediaGeneratorReference
    var onPreview: () -> Void
    var onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Button(action: onPreview) {
                preview
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(reference.previewURL == nil)
            .help(reference.previewURL == nil ? "This reference cannot be previewed directly." : "Open reference preview")

            if isHovered {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [.black.opacity(0.50), .black.opacity(0.12), .black.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 17, height: 17)
                            .background(Color.red.opacity(0.82), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    if reference.previewURL != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .padding(4)
                            .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity)
            }

            Text(reference.displayName)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(isHovered ? 0.52 : 0.34))
                .frame(width: 62, height: 62, alignment: .bottom)
        }
        .frame(width: 62, height: 62)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? MediaGeneratorPalette.accent.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 0.8)
        }
        .scaleEffect(isHovered ? 1.025 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let url = reference.previewURL {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange.opacity(0.82))
                            }
                    default:
                        Rectangle().fill(.white.opacity(0.06))
                    }
                }
            }
        } else if reference.url != nil {
            Rectangle()
                .fill(.white.opacity(0.06))
                .overlay {
                    Image(systemName: "link")
                        .foregroundStyle(.white.opacity(0.52))
                }
        } else {
            Rectangle().fill(.white.opacity(0.06))
        }
    }
}

private struct MediaGeneratorResultImage: View {
    enum Mode {
        case fill
        case fit
    }

    var url: URL
    var mode: Mode

    var body: some View {
        Group {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .modifier(MediaGeneratorImageSizing(mode: mode))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .modifier(MediaGeneratorImageSizing(mode: mode))
                    case .failure:
                        failedPlaceholder
                    default:
                        placeholder
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }

    private var failedPlaceholder: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
    }
}

private struct MediaGeneratorResultMedia: View {
    var task: MediaGeneratorTask
    var url: URL
    var mode: MediaGeneratorResultImage.Mode
    var autoplay = false
    var isMuted = true

    var body: some View {
        if task.category == .video {
            MediaGeneratorResultVideo(url: url, mode: mode, autoplay: autoplay, isMuted: isMuted)
        } else {
            MediaGeneratorResultImage(url: url, mode: mode)
        }
    }
}

private struct MediaGeneratorResultVideo: View {
    var url: URL
    var mode: MediaGeneratorResultImage.Mode
    var autoplay: Bool
    var isMuted: Bool

    var body: some View {
        ZStack {
            MediaGeneratorVideoPlayerView(
                url: url,
                mode: mode,
                isPlaying: autoplay,
                isMuted: isMuted
            )

            if !autoplay {
                LinearGradient(
                    colors: [.black.opacity(0.52), MediaGeneratorPalette.accent.opacity(0.22), .black.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: mode == .fill ? 30 : 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                    Text(videoLabel)
                        .font(.system(size: mode == .fill ? 10 : 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(8)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        }
    }

    private var videoLabel: String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? "Generated video" : url.lastPathComponent
        }
        return url.host ?? "Generated video"
    }
}

private struct MediaGeneratorVideoPlayerView: NSViewRepresentable {
    var url: URL
    var mode: MediaGeneratorResultImage.Mode
    var isPlaying: Bool
    var isMuted: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MediaGeneratorVideoPlayerContainerView {
        let view = MediaGeneratorVideoPlayerContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.update(url: url, mode: mode, isPlaying: isPlaying, isMuted: isMuted)
        return view
    }

    func updateNSView(_ nsView: MediaGeneratorVideoPlayerContainerView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(url: url, mode: mode, isPlaying: isPlaying, isMuted: isMuted)
    }

    static func dismantleNSView(_ nsView: MediaGeneratorVideoPlayerContainerView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: MediaGeneratorVideoPlayerContainerView?
        private var player: AVPlayer?
        private var currentURL: URL?
        private var observedItem: AVPlayerItem?
        private var shouldPlay = false

        override init() {
            super.init()
        }

        func attach(to view: MediaGeneratorVideoPlayerContainerView) {
            self.view = view
            view.playerLayer.player = player
        }

        func update(
            url: URL,
            mode: MediaGeneratorResultImage.Mode,
            isPlaying: Bool,
            isMuted: Bool
        ) {
            shouldPlay = isPlaying
            if currentURL != url || player == nil {
                configurePlayer(url: url)
            }
            view?.playerLayer.videoGravity = mode == .fill ? .resizeAspectFill : .resizeAspect
            player?.isMuted = isMuted
            if isPlaying {
                player?.play()
            } else {
                player?.pause()
            }
        }

        func cleanup() {
            removeEndObserver()
            player?.pause()
            player = nil
            currentURL = nil
            view?.playerLayer.player = nil
        }

        private func configurePlayer(url: URL) {
            removeEndObserver()
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            observedItem = item
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidReachEnd(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )
            self.player = player
            currentURL = url
            view?.playerLayer.player = player
        }

        private func removeEndObserver() {
            if let observedItem {
                NotificationCenter.default.removeObserver(
                    self,
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: observedItem
                )
            }
            observedItem = nil
        }

        @objc private func playerDidReachEnd(_ notification: Notification) {
            guard let item = notification.object as? AVPlayerItem,
                  item == observedItem
            else {
                return
            }
            player?.seek(to: .zero)
            if shouldPlay {
                player?.play()
            }
        }
    }
}

private final class MediaGeneratorVideoPlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.26).cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct MediaGeneratorImageSizing: ViewModifier {
    var mode: MediaGeneratorResultImage.Mode

    func body(content: Content) -> some View {
        switch mode {
        case .fill:
            content.scaledToFill()
        case .fit:
            content.scaledToFit()
        }
    }
}

private struct MediaGeneratorPreviewOverlay: View {
    var task: MediaGeneratorTask
    var isVideoMuted: Bool
    var onToggleVideoMute: () -> Void
    var onClose: () -> Void
    var onDownload: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.modelID.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MediaGeneratorPalette.modelPurple)
                        Text(task.displayTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if task.category == .video {
                            Button(action: onToggleVideoMute) {
                                Label(isVideoMuted ? "Sound Off" : "Sound On", systemImage: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            }
                            .buttonStyle(MediaGeneratorPillButtonStyle())
                            .help(isVideoMuted ? "Turn sound on" : "Mute video")
                        }

                        Button(action: onDownload) {
                            Label("Download", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(MediaGeneratorPillButtonStyle())

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(MediaGeneratorPillButtonStyle())
                    }
                }
                .padding(14)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }

                if let url = task.resultDisplayURL {
                    GeometryReader { proxy in
                        MediaGeneratorResultMedia(
                            task: task,
                            url: url,
                            mode: .fit,
                            autoplay: task.category == .video,
                            isMuted: isVideoMuted
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 0.8)
                    }
                    .onTapGesture { }
                }
            }
            .padding(28)
        }
    }
}

private struct MediaGeneratorReferencePreviewOverlay: View {
    var reference: MediaGeneratorReference
    var url: URL
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reference Image")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MediaGeneratorPalette.modelPurple)
                        Text(reference.displayName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(sourceText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(MediaGeneratorPillButtonStyle())
                }
                .padding(14)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }

                GeometryReader { proxy in
                    MediaGeneratorResultImage(url: url, mode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.8)
                }
                .onTapGesture { }
            }
            .padding(28)
        }
    }

    private var sourceText: String {
        if url.isFileURL {
            return url.path
        }
        return reference.url ?? url.absoluteString
    }
}

private struct MediaGeneratorTaskCard: View {
    var task: MediaGeneratorTask
    var isSelected: Bool
    var isVideoMuted: Bool
    var onPreview: () -> Void
    var onToggleVideoMute: () -> Void
    var onDownload: () -> Void
    var onCopy: () -> Void
    var onReveal: () -> Void
    var onUseAsReference: () -> Void
    var onApply: () -> Void
    var onStar: () -> Void
    var onDelete: () -> Void
    var onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(task.modelID.title)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(MediaGeneratorPalette.modelPurple)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.40))
                Spacer()
                if task.isStarred {
                    MediaGeneratorTaskTinyBadge(text: "STAR", color: .yellow)
                }
                if task.isLocallyCached {
                    MediaGeneratorTaskTinyBadge(text: "CACHED", color: .green)
                }
            }

            Text(task.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(task.status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Spacer()
                HStack(spacing: 8) {
                    Button(action: onStar) {
                        Image(systemName: task.isStarred ? "star.fill" : "star")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: .yellow, isActive: task.isStarred))
                    Button(action: onApply) {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle())
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: .red))
                }
            }

            if let error = task.errorMessage {
                MediaGeneratorCopyableErrorBlock(message: error)
            }

            if let url = task.resultDisplayURL {
                ZStack(alignment: .bottomLeading) {
                    MediaGeneratorResultMedia(
                        task: task,
                        url: url,
                        mode: .fit,
                        autoplay: isHovered,
                        isMuted: isVideoMuted
                    )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 180, maxHeight: 450)
                        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onTapGesture(perform: onPreview)

                    if task.category == .video {
                        MediaGeneratorVideoMuteButton(isMuted: isVideoMuted, action: onToggleVideoMute)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    if isHovered {
                        HStack(spacing: 6) {
                            if task.isLocallyCached {
                                MediaGeneratorOverlayIcon(systemName: "folder", action: onReveal)
                            }
                            MediaGeneratorOverlayIcon(systemName: "arrow.down.to.line", action: onDownload)
                            MediaGeneratorOverlayIcon(systemName: "doc.on.doc", action: onCopy)
                            if task.category == .image {
                                MediaGeneratorOverlayIcon(systemName: "photo.badge.plus", action: onUseAsReference)
                            }
                        }
                        .padding(8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            } else if task.status == .running || task.status == .queued {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let resultURL = task.resultURL {
                Text(resultURL)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? MediaGeneratorPalette.accent.opacity(0.10) : Color.white.opacity(isHovered ? 0.06 : 0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? MediaGeneratorPalette.accent.opacity(0.34) : Color.white.opacity(isHovered ? 0.12 : 0.08), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: task.createdAt)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: .secondary
        case .running: MediaGeneratorPalette.accent
        case .completed: .green
        case .failed: .red
        }
    }
}

private struct MediaGeneratorTaskGroupCard: View {
    var group: MediaGeneratorTaskGroup
    var isSelected: Bool
    var isVideoMuted: (MediaGeneratorTask) -> Bool
    var onPreview: (MediaGeneratorTask) -> Void
    var onToggleVideoMute: (MediaGeneratorTask) -> Void
    var onDownload: (MediaGeneratorTask) -> Void
    var onCopy: (MediaGeneratorTask) -> Void
    var onReveal: (MediaGeneratorTask) -> Void
    var onUseAsReference: (MediaGeneratorTask) -> Void
    var onApply: () -> Void
    var onStar: () -> Void
    var onDelete: () -> Void
    var onSelect: () -> Void
    @State private var isHovered = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        let representative = group.representative
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(representative.modelID.title)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(MediaGeneratorPalette.modelPurple)
                    .lineLimit(1)
                MediaGeneratorTaskTinyBadge(
                    text: "\(group.batchCount) \(representative.category.rawValue.uppercased())S",
                    color: MediaGeneratorPalette.accentLight
                )
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.40))
                Spacer()
                if group.isStarred {
                    MediaGeneratorTaskTinyBadge(text: "STAR", color: .yellow)
                }
                if group.isLocallyCached {
                    MediaGeneratorTaskTinyBadge(text: "CACHED", color: .green)
                }
            }

            Text(representative.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(group.statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("\(group.completedCount) done / \(group.failedCount) failed / \(group.runningCount) running")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: onStar) {
                        Image(systemName: group.isStarred ? "star.fill" : "star")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: .yellow, isActive: group.isStarred))
                    Button(action: onApply) {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle())
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: .red))
                }
            }

            if let errorMessage {
                MediaGeneratorCopyableErrorBlock(message: errorMessage)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(group.tasks.sorted(by: MediaGeneratorTaskGroup.sortTasks)) { task in
                    MediaGeneratorTaskGroupTile(
                        task: task,
                        isHovered: isHovered,
                        isVideoMuted: isVideoMuted(task),
                        onPreview: { onPreview(task) },
                        onToggleVideoMute: { onToggleVideoMute(task) },
                        onDownload: { onDownload(task) },
                        onCopy: { onCopy(task) },
                        onReveal: { onReveal(task) },
                        onUseAsReference: { onUseAsReference(task) }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? MediaGeneratorPalette.accent.opacity(0.10) : Color.white.opacity(isHovered ? 0.06 : 0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? MediaGeneratorPalette.accent.opacity(0.34) : Color.white.opacity(isHovered ? 0.12 : 0.08), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: group.representative.createdAt)
    }

    private var statusColor: Color {
        switch group.statusTitle {
        case MediaGeneratorTaskStatus.completed.title:
            .green
        case MediaGeneratorTaskStatus.failed.title:
            .red
        case "Partial":
            .orange
        default:
            MediaGeneratorPalette.accent
        }
    }

    private var errorMessage: String? {
        let messages = group.tasks
            .sorted(by: MediaGeneratorTaskGroup.sortTasks)
            .compactMap { task -> String? in
                guard let message = task.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty
                else {
                    return nil
                }
                return group.isBatch ? "#\(task.batchIndex): \(message)" : message
            }
        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }
}

private struct MediaGeneratorTaskGroupTile: View {
    var task: MediaGeneratorTask
    var isHovered: Bool
    var isVideoMuted: Bool
    var onPreview: () -> Void
    var onToggleVideoMute: () -> Void
    var onDownload: () -> Void
    var onCopy: () -> Void
    var onReveal: () -> Void
    var onUseAsReference: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    tileContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture {
                    if task.resultDisplayURL != nil {
                        onPreview()
                    }
                }

            HStack(spacing: 5) {
                MediaGeneratorTaskTinyBadge(text: "\(task.batchIndex)", color: .white.opacity(0.76))
                if task.status == .failed {
                    MediaGeneratorTaskTinyBadge(text: "FAILED", color: .red)
                } else if task.status == .running || task.status == .queued {
                    MediaGeneratorTaskTinyBadge(text: "RUNNING", color: MediaGeneratorPalette.accent)
                }
            }
            .padding(7)

            if task.category == .video, task.resultDisplayURL != nil {
                MediaGeneratorVideoMuteButton(isMuted: isVideoMuted, action: onToggleVideoMute)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if isHovered, task.resultDisplayURL != nil {
                HStack(spacing: 5) {
                    if task.isLocallyCached {
                        MediaGeneratorOverlayIcon(systemName: "folder", action: onReveal)
                    }
                    MediaGeneratorOverlayIcon(systemName: "arrow.down.to.line", action: onDownload)
                    MediaGeneratorOverlayIcon(systemName: "doc.on.doc", action: onCopy)
                    if task.category == .image {
                        MediaGeneratorOverlayIcon(systemName: "photo.badge.plus", action: onUseAsReference)
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if let url = task.resultDisplayURL {
            MediaGeneratorResultMedia(
                task: task,
                url: url,
                mode: .fit,
                autoplay: isHovered,
                isMuted: isVideoMuted
            )
        } else if task.status == .running || task.status == .queued {
            Rectangle()
                .fill(.white.opacity(0.055))
                .overlay {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
        } else {
            Rectangle()
                .fill(.white.opacity(0.055))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red.opacity(0.82))
                        Text(task.errorMessage ?? "Failed")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .help(task.errorMessage ?? "Failed")
                    }
                }
        }
    }
}

private struct MediaGeneratorCopyableErrorBlock: View {
    var message: String
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red.opacity(0.88))
                Spacer()
                Button {
                    copyMessage()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(MediaGeneratorTaskActionButtonStyle(tint: didCopy ? .green : .red))
            }

            ScrollView(.vertical) {
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.80))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 180)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.red.opacity(0.24), lineWidth: 0.8)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.red.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}

private struct MediaGeneratorReferencePasteMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onPasteImage: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onPasteImage: onPasteImage)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPasteImage = onPasteImage
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onPasteImage: () -> Void
        private var monitor: Any?

        init(isEnabled: Bool, onPasteImage: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onPasteImage = onPasteImage
        }

        func install() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let shortcutFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard let self,
                      self.isEnabled,
                      shortcutFlags == .command || shortcutFlags == [.command, .shift],
                      event.charactersIgnoringModifiers?.lowercased() == "v",
                      MediaGeneratorGearStore.pasteboardHasReferenceImage()
                else {
                    return event
                }
                self.onPasteImage()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private enum MediaGeneratorPalette {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let accent = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let accentLight = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let modelPurple = Color(red: 0.50, green: 0.35, blue: 0.84)
    static let border = Color.white.opacity(0.10)
    static let success = Color(red: 0.20, green: 0.83, blue: 0.60)
}

private struct MediaGeneratorSectionTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.46))
    }
}

private struct MediaGeneratorQuickPromptButton: View {
    var title: String
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.58))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(isHovered ? 0.11 : 0.06), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isHovered ? MediaGeneratorPalette.accent.opacity(0.35) : Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .offset(y: isHovered ? -1 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct MediaGeneratorQuickPromptIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.62))
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
    }
}

private struct MediaGeneratorOverlayIcon: View {
    var systemName: String
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        if case .destructive? = role {
            return .red.opacity(0.92)
        }
        if systemName == "star.fill" {
            return .yellow
        }
        return .white
    }
}

private struct MediaGeneratorVideoMuteButton: View {
    var isMuted: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isMuted ? .white.opacity(0.86) : MediaGeneratorPalette.accentLight)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isMuted ? .white.opacity(0.12) : MediaGeneratorPalette.accentLight.opacity(0.44), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Turn sound on" : "Mute video")
    }
}

private struct MediaGeneratorBackdrop: View {
    var body: some View {
        MediaGeneratorPalette.background
        .ignoresSafeArea()
    }
}

private struct MediaGeneratorThinScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.apply(in: view.window?.contentView ?? view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(in: nsView.window?.contentView ?? nsView)
        }
    }

    private static func apply(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.controlSize = .small
            scrollView.horizontalScroller?.controlSize = .small
        }
        for subview in view.subviews {
            apply(in: subview)
        }
    }
}

private struct MediaGeneratorSegmentButtonStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? .white : .white.opacity(0.56))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? MediaGeneratorPalette.accent.opacity(configuration.isPressed ? 0.95 : 1) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.001))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? MediaGeneratorPalette.accent.opacity(0.45) : .clear, lineWidth: 0.8)
            }
            .shadow(color: isActive ? MediaGeneratorPalette.accent.opacity(0.30) : .clear, radius: 8, y: 2)
    }
}

private struct MediaGeneratorPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.82))
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
            }
    }
}

private struct MediaGeneratorSelectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.88))
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
            }
    }
}

private struct MediaGeneratorFilterItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.64))
            .background(.white.opacity(configuration.isPressed ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
            }
    }
}

private struct MediaGeneratorClearCacheButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.58 : 0.62))
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.001), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MediaGeneratorPalette.border, lineWidth: 1)
            }
    }
}

private struct MediaGeneratorTaskActionButtonStyle: ButtonStyle {
    var tint: Color = .white
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle((isActive ? tint : .white.opacity(0.54)).opacity(configuration.isPressed ? 0.7 : 1))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill((isActive ? tint.opacity(0.10) : Color.clear).opacity(configuration.isPressed ? 1.3 : 1))
            )
    }
}

private struct MediaGeneratorFilterChipStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.bold))
            .foregroundStyle(isActive ? .white : .white.opacity(0.56))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? MediaGeneratorPalette.accent.opacity(configuration.isPressed ? 0.30 : 0.22) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? MediaGeneratorPalette.accent.opacity(0.42) : Color.white.opacity(0.08), lineWidth: 0.8)
            }
    }
}

private struct MediaGeneratorGhostButtonStyle: ButtonStyle {
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.72 : 0.86))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(backgroundColor.opacity(0.18), lineWidth: 0.8)
            }
    }

    private var foregroundColor: Color {
        if case .destructive? = role {
            return .red
        }
        return .white
    }

    private var backgroundColor: Color {
        if case .destructive? = role {
            return .red
        }
        return .white
    }
}

private struct MediaGeneratorPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .frame(height: 40)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [MediaGeneratorPalette.accent, Color(red: 0.39, green: 0.40, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .shadow(color: MediaGeneratorPalette.accent.opacity(0.24), radius: 12, y: 4)
    }
}
