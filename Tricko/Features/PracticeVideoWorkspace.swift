import AVFoundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum VideoTool: String, Identifiable, CaseIterable {
    case audio, speed, frame, studio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: return "Extract audio"
        case .speed: return "Change speed"
        case .frame: return "Reframe video"
        case .studio: return "Full editor"
        }
    }
    var detail: String {
        switch self {
        case .audio: return "Keep the sound as an M4A file."
        case .speed: return "Play a clip slower or faster."
        case .frame: return "Crop, rotate or flip a video."
        case .studio: return "Review moments, trim clips or adjust playback speed."
        }
    }
    var editorTab: String {
        switch self {
        case .audio: return "Audio"
        case .speed: return "Speed"
        case .frame: return "Frame"
        case .studio: return "Trim"
        }
    }
    var glyph: TrickoGlyph {
        switch self {
        case .audio: return .sound
        case .speed: return .play
        case .frame: return .feed
        case .studio: return .edit
        }
    }
}

struct ToolsView: View {
    let openSettings: () -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .subheadline) private var minimumToolWidth: CGFloat = 94
    @State private var editorRequest: EditorRequest?
    @State private var showingMembership = false

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let tool: VideoTool
        let movie: PracticeRecording?
    }

    private var latestImport: PracticeRecording? { library.movies.first { !$0.isExport } }
    private let shortcuts: [VideoTool] = [.speed, .frame, .audio]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 10) {
                    editorEntry
                    LocalVideoImportButtons(prominent: true) { movie in
                        if editorRequest == nil, !showingMembership {
                            editorRequest = EditorRequest(tool: .studio, movie: movie)
                        }
                    }
                }
                quickEdits
            }
            .trickoPage()
        }
        .foregroundStyle(TrickoStyle.paper)
        .trickoScreenBackground()
        .fullScreenCover(item: $editorRequest) { request in
            EditorSheet(initialMovie: request.movie, initialTool: request.tool)
        }
        .fullScreenCover(isPresented: $showingMembership) { MembershipView() }
    }

    private var header: some View {
        let title = LocalizedText("Tools").font(.stage(.largeTitle, weight: .bold)).accessibilityAddTraits(.isHeader)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title.fixedSize()
                Spacer(minLength: 0)
                headerActions.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                headerActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerActions: some View {
        TrickoGlassGroup {
            HStack(spacing: 8) {
                PlusEntryButton(active: commerce.premium, compact: true) { showingMembership = true }
                    .accessibilityIdentifier("tools.membership")
                IconButton(symbol: .settings, label: "Settings", action: openSettings)
                    .accessibilityIdentifier("tools.settings")
            }
        }
    }

    private var editorEntry: some View {
        let movie = latestImport
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { editorRequest = EditorRequest(tool: .studio, movie: movie) } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LocalizedText(VideoTool.studio.title)
                            .font(.stage(.title2, weight: .bold))
                        Glyph(symbol: .back, size: 13, tint: TrickoStyle.ink)
                            .rotationEffect(.degrees(180))
                    }
                    if let movie {
                        LocalizedText("Latest import").font(.stage(.caption))
                            .foregroundStyle(TrickoStyle.paperSecondary)
                        Text(verbatim: movie.title)
                            .font(.stage(.subheadline, weight: .semibold))
                            .lineLimit(2).truncationMode(.middle)
                    } else {
                        LocalizedText(VideoTool.studio.detail).font(.stage(.subheadline))
                            .foregroundStyle(TrickoStyle.paperSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    Color.clear.frame(width: 104)
                        .overlay {
                            if let movie {
                                LocalVideoCover(url: library.url(for: movie), cornerRadius: 0, maximumPixelSize: 480)
                            } else {
                                StagePhoto(asset: "VideoToolsPhoto", alignment: .trailing)
                            }
                        }
                        .clipped()
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(TrickoStyle.ink)
            .background(TrickoStyle.paper)
            .clipShape(shape)
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("tools.studio")
    }

    private var quickEdits: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedText("Quick edits").font(.stage(.headline, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                shortcutList
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(shortcuts) { tool in
                            shortcut(tool, stacked: true)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    shortcutList
                }
            }
        }
    }

    private var shortcutList: some View {
        VStack(spacing: 8) {
            ForEach(shortcuts) { tool in shortcut(tool, stacked: false) }
        }
    }

    private func shortcut(_ tool: VideoTool, stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                             : AnyLayout(HStackLayout(spacing: 12))
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { editorRequest = EditorRequest(tool: tool, movie: latestImport) } label: {
            layout {
                Glyph(symbol: tool.glyph, size: 23, tint: TrickoStyle.coolAccent)
                LocalizedText(tool.title).font(.stage(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(minWidth: stacked ? minimumToolWidth : nil, maxWidth: .infinity,
                   maxHeight: stacked ? .infinity : nil, alignment: .topLeading)
            .frame(minHeight: 48, alignment: .leading)
            .background { StageSurface(tone: .smoke, radius: 14) }
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(Text(verbatim: L10n.text(tool.detail, language: AppLanguage.from(locale))))
        .accessibilityIdentifier("tools.\(tool.rawValue)")
    }
}

struct LocalVideoImportButtons: View {
    var prominent = false
    let onImport: (PracticeRecording) -> Void
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var picker: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var importTask: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        let buttonSpacing: CGFloat = prominent ? 12 : 8
        let stackedButtons = VStack(alignment: .leading, spacing: buttonSpacing) {
            filesButton
            photosButton
        }
        VStack(alignment: .leading, spacing: 12) {
            TrickoGlassGroup {
                if typeSize.isAccessibilitySize {
                    stackedButtons
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: buttonSpacing) {
                            filesButton.fixedSize(horizontal: !prominent, vertical: false)
                            photosButton.fixedSize(horizontal: !prominent, vertical: false)
                        }
                        stackedButtons
                    }
                }
            }
            .disabled(importTask != nil)
            if importTask != nil {
                StageLoadingIndicator(title: "Importing…", compact: true)
            }
            if let error { ErrorNote(message: error) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url):
                importVideo { try await library.importMovie(url) }
            case .failure(let error):
                showError(error)
            }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $picker, matching: .videos, photoLibrary: .shared())
        .onChange(of: picker) { _, item in
            guard let item else { return }
            picker = nil
            importVideo {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                    throw TrickoError.unsupportedMedia
                }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                return try await library.importMovie(movie.url, title: "Imported video")
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private var filesButton: some View {
        sourceButton("Files", symbol: .folder, primary: true) {
            error = nil
            showingFiles = true
        }
        .accessibilityLabel(LocalizedStringKey("Browse Files"))
        .accessibilityIdentifier("video.importFiles")
    }

    private var photosButton: some View {
        sourceButton("Photos", symbol: .feed, primary: false) {
            error = nil
            showingPhotos = true
        }
        .accessibilityLabel(LocalizedStringKey("Choose from Photos"))
        .accessibilityIdentifier("video.importPhotos")
    }

    @ViewBuilder private func sourceButton(
        _ title: String, symbol: TrickoGlyph, primary: Bool, action: @escaping () -> Void
    ) -> some View {
        if prominent {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let foreground = primary ? TrickoStyle.accent : TrickoStyle.paper
            Button(action: action) {
                let label = HStack(spacing: 10) {
                    Glyph(symbol: symbol, size: 23, tint: foreground)
                    LocalizedText(title).font(.stage(.headline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64)

                label.trickoGlass(in: shape, tint: primary ? TrickoStyle.accent.opacity(0.24) : nil)
                    .contentShape(.interaction, shape)
            }.buttonStyle(PressStyle())
        } else {
            Button(action: action) { LocalizedText(title) }
                .buttonStyle(EmptyStateActionStyle(primary: primary, symbol: symbol, minHeight: 52))
        }
    }

    private func importVideo(_ load: @escaping () async throws -> PracticeRecording) {
        guard importTask == nil else { return }
        error = nil
        importTask = Task {
            defer { importTask = nil }
            do {
                let movie = try await load()
                try Task.checkCancellation()
                onImport(movie)
            } catch { showError(error) }
        }
    }

    private func showError(_ error: Error) {
        let failure = error as NSError
        guard !(error is CancellationError),
              !(failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError),
              !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) else { return }
        self.error = error.localizedDescription
    }
}

struct LocalVideoCover: View {
    let url: URL
    var cornerRadius: CGFloat = 8
    var maximumPixelSize: CGFloat = 288
    var placeholderSymbol: TrickoGlyph? = .feed
    @State private var image: UIImage?

    var body: some View {
        TrickoStyle.raised
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    StageCoverPlaceholder(symbol: placeholderSymbol)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
            .task(id: url) {
                image = nil
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)
                if let frame = try? await generator.image(at: .zero), !Task.isCancelled {
                    image = UIImage(cgImage: frame.image)
                }
            }
    }
}

struct EditorSheet: View {
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool)
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}

func usesVideoWorkspaceColumns(in size: CGSize, typeSize: DynamicTypeSize) -> Bool {
    size.width >= (typeSize.isAccessibilitySize ? 920 : 690) || (size.height < 460 && size.width >= 540)
}

private struct EditorWorkspace: View {
    @State private var showingPresets = false
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let initialTool: VideoTool
    @StateObject private var editor = VideoEditor()
    @State private var selected: PracticeRecording?
    @State private var reviewingVideo: VideoReviewRoute?
    @State private var error: String?
    @State private var shareURL: SharedFile?
    @State private var tool = "Trim"
    @State private var exportTask: Task<Void, Never>?
    @State private var sourceTask: Task<Void, Never>?
    private let tools = ["Trim", "Frame", "Speed", "Audio", "Export"]
    private var canChangeReviewSettings: Bool {
        !departure.running && !editor.isExporting && !editor.isPreparingPreview && !editor.isLoading && editor.duration > 0
    }
    init(initialMovie: PracticeRecording? = nil, initialTool: VideoTool = .studio) {
        self.initialTool = initialTool
        _selected = State(initialValue: initialMovie)
        _tool = State(initialValue: initialTool.editorTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let selected {
                    fileHeading(selected)
                } else {
                    LocalizedText(initialTool.title).font(.stage(.title2, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                IconButton(symbol: .close, label: "Close", action: close)
            }
            .pageHorizontalMargins().padding(.vertical, 6)
            Divider().overlay(TrickoStyle.line).accessibilityHidden(true)
            if let selected {
                videoWorkspace(selected)
            } else {
                ScrollView { importWorkspace.trickoPage() }
            }
        }
            .frame(maxWidth: 1160).frame(maxWidth: .infinity)
            .trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
            .onReceive(editor.preview.$error) { message in
                if let message { editor.error = "Preview could not play. \(message)" }
            }
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(item: $reviewingVideo) { VideoReviewView(movie: $0.movie, startingAt: $0.startingAt) }
            .onChange(of: selected?.id, initial: true) { _, _ in openSelectedMovie() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.preview.pause() } }
            .onDisappear {
                // A full-screen review temporarily covers the editor and shares its source video.
                guard reviewingVideo == nil, shareURL == nil else {
                    editor.preview.pause()
                    return
                }
                sourceTask?.cancel()
                editor.close()
                exportTask?.cancel()
            }
    }

    private func openSelectedMovie() {
        guard let selected else { sourceTask?.cancel(); return }
        let url = library.url(for: selected)
        guard editor.sourceURL != url || (!editor.isLoading && editor.duration <= 0) else { return }
        sourceTask?.cancel()
        sourceTask = Task {
            guard !Task.isCancelled else { return }
            await editor.open(url)
        }
    }

    private func close() {
        departure.request { dismiss() }
    }

    private func videoWorkspace(_ selected: PracticeRecording) -> some View {
        GeometryReader { viewport in
            let size = viewport.size
            let split = usesVideoWorkspaceColumns(in: size, typeSize: typeSize)
            if !split && (size.height < 420 || typeSize.isAccessibilitySize) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewTray(maxVideoHeight: 260)
                        inspector(selected)
                    }.padding(.bottom, 16)
                }
            } else {
                let layout = split
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                layout {
                    previewTray(maxVideoHeight: split ? max(80, size.height - 86) : size.height * 0.42,
                               compactControls: split && (size.height < 370 || typeSize.isAccessibilitySize))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: split ? size.width * 0.51 : nil)
                    ScrollView {
                        inspector(selected).padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .pageHorizontalMargins().padding(.top, 12)
    }

    private func inspector(_ selected: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = editor.error { ErrorNote(message: error) }
            if initialTool == .studio {
                StageFilter(values: tools, selected: tool) { tool = $0 }
                    .disabled(departure.running || editor.isPreparingPreview)
            }
            controls.disabled(departure.running || editor.isExporting || editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
            if initialTool == .studio {
                VideoReviewButton(movie: library.movies.first { $0.id == selected.id } ?? selected) {
                    editor.preview.pause()
                    let time = editor.preview.player.currentTime().seconds
                    let isAtSourceTime = editor.preview.loadedURL == library.url(for: selected) && !editor.preview.isSeeking
                    reviewingVideo = VideoReviewRoute(movie: selected, startingAt: isAtSourceTime && time.isFinite ? time : nil)
                }
                .disabled(!canChangeReviewSettings)
                reviewPresets
            }
            if let error { ErrorNote(message: error) }
            if departure.running {
                VStack(alignment: .leading, spacing: 12) {
                    if editor.isExporting {
                        LocalizedText("Exporting · \(Int(editor.progress * 100))%")
                            .font(.stage(.subheadline, weight: .semibold).monospacedDigit())
                        StageProgressTrack(value: Double(editor.progress))
                    } else {
                        HStack(spacing: 8) {
                            StageActivityMark()
                            LocalizedText("Preparing export…")
                                .font(.stage(.subheadline, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ActionButton(title: "Cancel export", primary: false) { departure.request() }
                }
                .padding(16)
                .trickoGlass(in: .rect(cornerRadius: 18), fallback: TrickoStyle.surface, interactive: false)
            } else {
                editingActions(selected)
            }
        }
    }

    private func fileHeading(_ movie: PracticeRecording) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(initialTool.title)
                    .font(.stage(.caption, weight: .semibold)).foregroundStyle(TrickoStyle.coolAccent)
                Text(verbatim: movie.title).font(.stage(.headline, weight: .semibold)).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !departure.running, !editor.isExporting, !editor.isPreparingPreview {
                Button {
                    showingPresets = false
                    selected = nil
                    error = nil
                    editor.close()
                } label: {
                    LocalizedText("Change").font(.stage(.footnote, weight: .semibold))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .trickoGlass(in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private func previewTray(maxVideoHeight: CGFloat, compactControls: Bool = false) -> some View {
        let previewWidth = maxVideoHeight * editor.previewAspectRatio
        return VStack(spacing: 0) {
            VideoSurface(player: editor.preview.player, fill: false)
                .aspectRatio(editor.previewAspectRatio, contentMode: .fit)
                .frame(maxWidth: previewWidth)
                .frame(maxWidth: .infinity)
                .background(.black)
                .overlay {
                    if editor.isLoading || editor.isPreparingPreview {
                        StageLoadingIndicator(title: editor.isLoading ? "Preparing your video…" : "Preparing preview…",
                                              compact: true)
                    }
                }
            EditorPlaybackBar(playback: editor.preview, timeline: editor.preview.timeline,
                              disabled: editor.isLoading || editor.isPreparingPreview || departure.running,
                              compact: compactControls)
                .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .background(TrickoStyle.surface)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(TrickoStyle.line)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func editingActions(_ movie: PracticeRecording) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
            ActionButton(title: initialTool == .audio ? "Export audio as M4A" : "Export video") {
                export(audio: initialTool == .audio, title: movie.title)
            }
        }
        .disabled(editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
    }

    private var reviewPresets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingPresets.toggle() } label: {
                LocalizedText(showingPresets ? "Hide review presets" : "Review presets")
            }
            .buttonStyle(EmptyStateActionStyle(primary: false, symbol: .settings))
            .accessibilityAddTraits(showingPresets ? .isSelected : [])
            .accessibilityIdentifier("editor.reviewPresets")
            if showingPresets {
                ReviewPresetControls(recipe: editor.recipe, preparing: editor.isPreparingPreview) { updated in
                    guard canChangeReviewSettings else { return }
                    editor.recipe = updated
                    Task { await editor.applyPreview(autoplay: false) }
                }
            }
        }
        .disabled(!canChangeReviewSettings)
    }

    private var importWorkspace: some View {
        let imports = library.movies.filter { !$0.isExport }
        return VStack(alignment: .leading, spacing: 18) {
            EmptyStatePanel(symbol: .feed) {
                EmptyStateCopy(title: "Start with a video.",
                               message: "Choose a clip from your device. We’ll keep your original untouched.")
                LocalVideoImportButtons { movie in
                    if selected == nil { choose(movie) }
                }
            }
            if !imports.isEmpty {
                SectionLabel(title: "Recent imports").padding(.top, 8)
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(imports) { movie in
                        Button { choose(movie) } label: {
                            HStack(spacing: 14) {
                                LocalVideoCover(url: library.url(for: movie)).frame(width: 76, height: 48)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: movie.title).font(.stage(.headline)).lineLimit(1)
                                    LocalizedDateText(date: movie.date).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                                }
                                Spacer(minLength: 0)
                                Glyph(symbol: .edit, size: 17, tint: TrickoStyle.accent)
                            }
                            .padding(.vertical, 4).frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tool {
            case "Trim":
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { LocalizedText("Start"); Spacer(); Text(verbatim: durationLabel(editor.recipe.start)).monospacedDigit() }
                TrickoScrubber(value: Binding(get: { editor.recipe.start }, set: { editor.recipe.start = min($0, editor.recipe.end - 0.1); editor.preview.seek($0) }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { LocalizedText("End"); Spacer(); Text(verbatim: durationLabel(editor.recipe.end)).monospacedDigit() }
                TrickoScrubber(value: Binding(get: { editor.recipe.end }, set: { editor.recipe.end = max($0, editor.recipe.start + 0.1) }), range: 0...max(0.1, editor.duration), label: "Trim end")
                LocalizedText("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))").font(.stage(.footnote)).foregroundStyle(TrickoStyle.accent)
            case "Frame":
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                ActionButton(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°", primary: false) { editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4 }
                ActionButton(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off", primary: false) { editor.recipe.mirrored.toggle() }
                LocalizedText("Frames crop from the center. Use Preview changes to inspect the result.").font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
            case "Speed":
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
            case "Audio":
                if initialTool == .audio {
                    LocalizedText("Extract the original audio track into an M4A file. Videos without an audio track cannot be converted.")
                        .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                } else {
                    ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) { editor.recipe.muted.toggle() }
                    ActionButton(title: "Extract audio as M4A", primary: false) { export(audio: true, title: selected?.title ?? "Audio") }
                    LocalizedText("Audio extraction uses your trim and speed settings.").font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                }
            default:
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                LocalizedText("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
            }
        }.padding(22).background(TrickoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func choose(_ movie: PracticeRecording) {
        selected = movie
        error = nil
    }
    private func export(audio: Bool, title: String) {
        guard exportTask == nil else { return }
        error = nil
        exportTask = Task {
            defer { exportTask = nil; departure.finish() }
            guard let output = await editor.export(audioOnly: audio) else { return }
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); return }
            do {
                defer { try? FileManager.default.removeItem(at: output) }
                let saved = try await library.importMovie(output, exported: true, title: title + (audio ? " · Audio" : " · Edit"))
                let share = try await library.shareFile(for: saved)
                if !Task.isCancelled { shareURL = SharedFile(url: share) }
            } catch is CancellationError { }
            catch { self.error = "The export finished but could not be added to your library. \(error.localizedDescription)" }
        }
        departure.begin { exportTask?.cancel(); editor.cancelExport() }
    }
}

private struct ReviewPresetControls: View {
    let recipe: EditRecipe
    let preparing: Bool
    let apply: (EditRecipe) -> Void
    @AppStorage("tricko.reviewPreset.v1") private var savedData: Data?
    @State private var status: String?

    private var savedPreset: ReviewPreset? {
        guard let savedData, let preset = try? JSONDecoder().decode(ReviewPreset.self, from: savedData),
              preset.isValid else { return nil }
        return preset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if preparing {
                StageLoadingIndicator(title: "Preparing preview…", compact: true)
            } else {
                LocalizedText("Presets keep your trim points. Play the preview to check the result.")
                    .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                presetRow("Slow mirror", "Half speed with a horizontal flip.") { settings in
                    settings.speed = 0.5
                    settings.mirrored = true
                }
                Divider().overlay(TrickoStyle.line)
                presetRow("Slow portrait", "0.75× speed in a 9:16 frame.") { settings in
                    settings.speed = 0.75
                    settings.frame = .portrait
                }
                if let savedPreset {
                    Divider().overlay(TrickoStyle.line)
                    presetRow("My preset", "Apply the settings you saved on this device.") { settings in
                        settings = savedPreset.applied(to: settings)
                    }
                }
            }
            ActionButton(title: savedPreset == nil ? "Save current settings" : "Update my preset", primary: false, action: save)
            if let status {
                LocalizedText(status).font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(14)
        .background { StageSurface(tone: .smoke) }
    }

    private func presetRow(_ title: String, _ detail: String, update: @escaping (inout EditRecipe) -> Void) -> some View {
        Button {
            var updated = recipe
            update(&updated)
            apply(updated)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(title).font(.stage(.headline))
                    LocalizedText(detail).font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 13, tint: TrickoStyle.accent).rotationEffect(.degrees(180))
            }
            .padding(.vertical, 12).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func save() {
        let preset = ReviewPreset(recipe)
        guard preset.isValid, let data = try? JSONEncoder().encode(preset) else {
            status = "Couldn’t save the preset."
            return
        }
        savedData = data
        status = "Preset saved on this device."
    }
}

struct EditorPlaybackBar: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: PlaybackTimeline
    let disabled: Bool
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrubbing = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize && !compact
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            IconButton(symbol: playback.isPlaying ? .pause : .play,
                       label: playback.isPlaying ? "Pause preview" : "Play preview") { playback.toggle() }
            PlayerProgressControl(playback: playback, timeline: timeline, enabled: !disabled,
                                  canResume: !disabled, scrubbing: $scrubbing)
            if !compact {
                Text(verbatim: "\(durationLabel(timeline.elapsed)) / \(durationLabel(timeline.duration))")
                    .font(.stage(.caption, weight: .medium).monospacedDigit())
                    .foregroundStyle(TrickoStyle.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .disabled(disabled || timeline.duration <= 0 || playback.error != nil)
    }
}
struct FlowChoices: View {
    let values: [String]
    let selected: String
    var action: (String) -> Void
    var body: some View {
        StageFilter(values: values, selected: selected, select: action)
    }
}
struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
