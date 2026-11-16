import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingMembership = false
    @State private var showingExportMembership = false
    let edit: (PracticeRecording) -> Void
    let watchLessons: () -> Void
    @Binding var filter: String
    @State private var player: PlayerRoute?
    @State private var reviewingVideo: PracticeRecording?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var category: Category { Category(rawValue: filter) ?? .imports }
    private var localMovies: [PracticeRecording] {
        library.movies.filter { $0.isExport == (category == .exports) }
    }

    private enum Category: String, CaseIterable, Identifiable {
        case imports = "Imports"
        case exports = "Exports"
        case saved = "Saved"
        case offline = "Downloads"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .saved: "Favorites"
            case .offline: "Offline videos"
            case .imports, .exports: rawValue
            }
        }
        var glyph: TrickoGlyph {
            switch self {
            case .saved: .bookmark
            case .offline: .download
            case .imports: .folder
            case .exports: .edit
            }
        }

        var emptyTitle: String {
            switch self {
            case .saved: "No favorites yet"
            case .offline: "No offline videos yet"
            case .imports: "No imported videos yet"
            case .exports: "No exports yet"
            }
        }

        var emptyMessage: String {
            switch self {
            case .saved: "Tap Favorite while watching a lesson to save it here."
            case .offline: "Download a lesson from its playback options to watch without a connection."
            case .imports: "Choose a video from Photos or Files to start editing."
            case .exports: "Export a video or audio track from the editor to find it here."
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                libraryHeader
                categoryIndex
                if category == .imports {
                    if localMovies.isEmpty { emptyArchive }
                    LocalVideoImportButtons(onImport: edit)
                }
                librarySection
            }.trickoPage()
        }
            .trickoScreenBackground()
            .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .sheet(item: $reviewingVideo) { VideoReviewView(movie: $0) }
            .sheet(isPresented: $showingMembership) { MembershipView() }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removingDownload) { video in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeading(title: "Remove offline video?") { removingDownload = nil }
                        Text(verbatim: video.clip.title).font(.stage(.headline)).lineLimit(3)
                        LocalizedText("This removes only the offline copy. Your favorite stays saved.")
                            .foregroundStyle(TrickoStyle.secondary)
                        ActionButton(title: "Remove download", primary: false) {
                            offline.remove(video); removingDownload = nil
                        }
                        ActionButton(title: "Keep it") { removingDownload = nil }
                    }.padding(24)
                }.trickoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete this local copy?") { removing = nil }
                        Text(verbatim: movie.title).font(.stage(.headline))
                        LocalizedText("This removes the local copy. Your original file stays where it is.").foregroundStyle(TrickoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Keep it", primary: false) { removing = nil }
                    }.padding(24)
                }.trickoScreenBackground().presentationDetents([.medium, .large])
            }
    }

    private var libraryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                libraryHeading.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                membershipButton.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                libraryHeading
                membershipButton
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var libraryHeading: some View {
        LocalizedText("Library")
            .font(.stage(.title2, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var membershipButton: some View {
        PlusEntryButton(active: commerce.premium, compact: true) { showingMembership = true }
            .accessibilityIdentifier("library.membership")
    }

    private var categoryIndex: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Category.allCases) { entry in
                let selected = category == entry
                let labelColor = selected ? TrickoStyle.ink : TrickoStyle.paper
                Button { filter = entry.rawValue } label: {
                    HStack(spacing: 7) {
                        Glyph(symbol: entry.glyph, size: 16, tint: selected ? TrickoStyle.ink : TrickoStyle.coolAccent)
                        LocalizedText(entry.title).font(.stage(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(count(in: entry), format: .number.locale(locale))
                            .font(.stage(.footnote, weight: .medium).monospacedDigit())
                            .foregroundStyle(selected ? TrickoStyle.paperSecondary : TrickoStyle.secondary)
                    }
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background {
                        if selected { StageSurface(tone: .ivory, radius: 12) }
                    }
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(Text(verbatim: L10n.text(entry.title, language: AppLanguage.from(locale))))
                .accessibilityValue(Text(count(in: entry), format: .number.locale(locale)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background { StageSurface(tone: .smoke, radius: 17) }
    }

    private var librarySection: some View {
        let total = count(in: category)
        return VStack(alignment: .leading, spacing: 16) {
            if total == 0 {
                if category == .offline, offline.isRestoring {
                    AccountLoadingIndicator(title: "Loading downloads…").frame(maxWidth: .infinity)
                } else if category != .imports, category != .offline || offline.downloadingID == nil {
                    emptyCategory
                }
                if category == .offline {
                    downloadStatus
                    DownloadAllowanceSummary()
                }
            } else {
                switch category {
                case .saved:
                    LazyVStack(spacing: 4) {
                        ForEach(library.favorites) { clip in favoriteRow(clip) }
                    }
                case .offline:
                    DownloadAllowanceSummary()
                    downloadStatus
                    LazyVStack(spacing: 4) {
                        ForEach(offline.videos) { video in downloadRow(video) }
                    }
                case .imports, .exports:
                    localGallery
                }
            }
        }
    }

    private var emptyCategory: some View {
        VStack(alignment: .leading, spacing: 16) {
            if category == .exports {
                emptyArchive
                LocalVideoImportButtons(onImport: edit)
            } else {
                EmptyStateCopy(title: category.emptyTitle, message: category.emptyMessage)
                Button(action: watchLessons) { LocalizedText("Watch lessons") }
                    .buttonStyle(EmptyStateActionStyle(symbol: .play))
            }
        }
    }

    private var emptyArchive: some View {
        EmptyStateCopy(title: category.emptyTitle, message: category.emptyMessage)
            .padding(18).frame(minHeight: 182, alignment: .bottomLeading)
            .background {
                StagePhoto(asset: "VideoArchivePhoto")
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.28),
                            .init(color: TrickoStyle.background.opacity(0.86), location: 0.73),
                            .init(color: TrickoStyle.background, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
            .clipShape(.rect(cornerRadius: 19))
    }

    private var localGallery: some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 148), spacing: 12, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(localMovies) { movie in movieCard(movie) }
        }
    }

    private func count(in entry: Category) -> Int {
        switch entry {
        case .saved: library.favorites.count
        case .offline: offline.videos.count
        case .imports: library.movies.lazy.filter { !$0.isExport }.count
        case .exports: library.movies.lazy.filter(\.isExport).count
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        if offline.downloadingID != nil || offline.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if offline.downloadingID != nil {
                    if let title = offline.currentTitle {
                        Text(verbatim: title).font(.stage(.subheadline, weight: .semibold)).lineLimit(2)
                    }
                    LocalizedText("Downloading · \(Int(offline.progress * 100))%")
                        .font(.stage(.caption)).monospacedDigit()
                    Button("Cancel download") { Task { await offline.cancel() } }
                        .buttonStyle(LibraryActionStyle())
                }
                if let error = offline.error {
                    ErrorNote(message: error)
                    if offline.downloadingID != nil {
                        Button("Retry") { Task { await offline.retryCompletion() } }
                            .buttonStyle(LibraryActionStyle())
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TrickoStyle.surface, in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func favoriteRow(_ clip: LessonClip) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                HStack(spacing: 10) {
                    lessonTitle(clip)
                    playableCover(clip.coverURL, width: 60, height: 64)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            removeButton(.bookmark, title: "Remove saved video") { library.toggle(clip) }
        }
        .modifier(LibraryRowSurface())
    }

    private func playableCover(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
        MediaCover(url: url)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 5))
            .overlay(alignment: .bottomTrailing) {
                Glyph(symbol: .play, size: 15, tint: TrickoStyle.paper)
                    .frame(width: 28, height: 28)
                    .background(TrickoStyle.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 4))
                    .padding(3).allowsHitTesting(false)
            }.accessibilityHidden(true)
    }

    private func lessonTitle(_ clip: LessonClip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: clip.title).font(.stage(.title3, display: true)).lineLimit(3)
            if !clip.channel.isEmpty {
                Text(verbatim: clip.channel).font(.stage(.caption))
                    .foregroundStyle(TrickoStyle.secondary).lineLimit(2)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func downloadRow(_ video: OfflineVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { playDownload(video) } label: {
                HStack(spacing: 12) {
                    itemGlyph(.play)
                    Text(verbatim: video.clip.title).font(.stage(.title3, display: true)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            HStack(spacing: 8) {
                VideoExportEntry(clip: offline.playable(video.clip), compact: true)
                Spacer(minLength: 0)
                removeButton(.close, title: "Remove download") { removingDownload = video }
            }
        }
        .modifier(LibraryRowSurface())
    }

    private func movieCard(_ movie: PracticeRecording) -> some View {
        let isAudio = movie.filename.hasSuffix(".m4a")
        return VStack(alignment: .leading, spacing: 2) {
            if isAudio {
                movieLabel(movie, isAudio: true)
            } else {
                Button { edit(movie) } label: { movieLabel(movie, isAudio: false) }
                    .buttonStyle(PressStyle())
                    .accessibilityHint(LocalizedStringKey("Full editor"))
                if !movie.isExport {
                    VideoReviewButton(movie: movie) { reviewingVideo = movie }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
            HStack(spacing: 2) {
                Button { shareMovie(movie) } label: {
                    LocalizedText(sharingMovieID == movie.id ? "Preparing export…" : "Share")
                        .font(.stage(.footnote, weight: .semibold))
                        .foregroundStyle(TrickoStyle.coolAccent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).disabled(sharingMovieID != nil)
                removeButton(.close, title: "Delete local file") { removing = movie }
            }
            .padding(.leading, 12).padding(.trailing, 4)
        }
        .background { StageSurface(tone: .smoke, radius: 15) }
        .clipShape(.rect(cornerRadius: 15))
    }

    private func movieLabel(_ movie: PracticeRecording, isAudio: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isAudio {
                    TrickoStyle.raised.overlay {
                        Glyph(symbol: .sound, size: 29, tint: TrickoStyle.coolAccent)
                    }
                } else {
                    LocalVideoCover(url: library.url(for: movie), cornerRadius: 0, maximumPixelSize: 760)
                }
            }
            .aspectRatio(1.60, contentMode: .fit)
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    Text(verbatim: (movie.filename as NSString).pathExtension.uppercased())
                        .font(.stage(.caption2, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(TrickoStyle.paper)
                        .background(TrickoStyle.ink.opacity(0.92), in: Capsule())
                    Spacer(minLength: 0)
                    if !isAudio {
                        Glyph(symbol: .edit, size: 14, tint: TrickoStyle.paper)
                            .frame(width: 32, height: 32)
                            .background(TrickoStyle.ink.opacity(0.92), in: Circle())
                    }
                }
                .padding(8).allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: movie.title).font(.stage(.subheadline, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(TrickoStyle.paper)
                LocalizedDateText(date: movie.date)
                    .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 2)
        }
        .contentShape(Rectangle())
    }

    private func itemGlyph(_ symbol: TrickoGlyph) -> some View {
        Glyph(symbol: symbol, size: 19, tint: TrickoStyle.accent)
            .frame(width: 46, height: 46)
            .background(TrickoStyle.raised, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private func removeButton(_ symbol: TrickoGlyph, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 16, tint: TrickoStyle.accent)
                .frame(width: 36, height: 36)
                .background(TrickoStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: L10n.text(title, language: AppLanguage.from(locale))))
    }

    private func playDownload(_ video: OfflineVideo) {
        let clips = offline.videos.compactMap { item -> LessonClip? in
            offline.cached(item.id) == nil ? nil : offline.playable(item.clip)
        }
        if clips.contains(where: { $0.id == video.id }) {
            player = PlayerRoute(clips: clips, startID: video.id)
        } else { offline.error = "This download is no longer on this device. Download it again." }
    }

    private func shareMovie(_ movie: PracticeRecording) {
        guard commerce.canExportMedia else {
            showingExportMembership = true
            return
        }
        sharingMovieID = movie.id
        Task {
            defer { sharingMovieID = nil }
            do { sharing = SharedFile(url: try await library.shareFile(for: movie, commerce: commerce)) }
            catch { library.error = error.localizedDescription }
        }
    }
}

private struct LibraryRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().overlay(TrickoStyle.line).allowsHitTesting(false) }
    }
}

private struct LibraryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.stage(.subheadline, weight: .semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(TrickoStyle.ink)
            .background { StageSurface(tone: .ivory, radius: 12) }
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.58 : configuration.isPressed ? 0.72 : 1)
    }
}

struct OfflineDownloadButton: View {
    let clip: LessonClip
    var starting = false
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DownloadAllowanceSummary()
            if offline.cached(clip.id) != nil || clip.playbackURL.isFileURL {
                LocalizedText("Available offline").font(.stage(.subheadline)).foregroundStyle(TrickoStyle.accent)
                DownloadCompletionNotice()
            } else if starting || offline.preparingID == clip.id {
                LocalizedText("Preparing download…").font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
            } else if offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.stage(.caption))
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            } else {
                ActionButton(title: "Download for offline", primary: false) {
                    if quota.mayDownload(clip.id, premium: commerce.premium) {
                        Task { await offline.download(clip) }
                    } else { downloadGate = true }
                }.disabled(offline.busy || clip.playbackURL.isFileURL)
                    .accessibilityIdentifier("player.downloadOffline")
                if offline.isRestoring {
                    LocalizedText("Restoring downloads…").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                } else if offline.busy {
                    LocalizedText("Another download is in progress.").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                }
            }
            VideoExportEntry(clip: clip)
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID == clip.id {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
        }.sheet(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

struct VideoExportEntry: View {
    let clip: LessonClip
    var compact = false
    @State private var showingExport = false
    @EnvironmentObject private var commerce: CommerceStore
    var body: some View {
        Group {
            if compact {
                Button("Export") { showingExport = true }.buttonStyle(LibraryActionStyle())
            } else {
                ActionButton(title: "Export video", primary: false) { showingExport = true }
            }
        }.accessibilityIdentifier("player.openExport")
            .sheet(isPresented: $showingExport) {
                if commerce.canExportMedia { OfflineExportSheet(clip: clip) }
                else { MembershipView(exportRequired: true) }
            }
    }
}

private struct OfflineExportSheet: View {
    let clip: LessonClip
    @Environment(\.dismiss) private var dismiss
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeading(title: "Export video") { departure.request { dismiss() } }
                Text(verbatim: clip.title).font(.stage(.subheadline)).lineLimit(2)
                OfflineExportButton(clip: clip)
            }.padding(22)
        }.trickoScreenBackground().presentationDetents([.medium, .large])
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}

@MainActor
final class ExportDeparture: ObservableObject {
    @Published private(set) var running = false
    @Published var confirming = false
    private var cancellation: (() -> Void)?
    private var afterCancellation: (() -> Void)?
    func begin(cancel: @escaping () -> Void) { running = true; cancellation = cancel }
    func finish() {
        running = false; cancellation = nil
        confirming = false; afterCancellation = nil
    }
    func request(_ close: @escaping () -> Void = {}) {
        guard running else { close(); return }
        afterCancellation = close; confirming = true
    }
    func keepWorking() { confirming = false; afterCancellation = nil }
    func stop() {
        let close = afterCancellation
        cancellation?()
        confirming = false; afterCancellation = nil
        close?()
    }
}

struct ExportDepartureProtection: ViewModifier {
    @ObservedObject var departure: ExportDeparture
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(departure.running)
            .accessibilityHidden(departure.confirming)
            .overlay {
                if departure.confirming {
                    GeometryReader { container in
                        ScrollView {
                            VStack(spacing: 18) {
                                LocalizedText("Stop this export?").font(.stage(.headline))
                                LocalizedText("The export is still in progress. Leaving now cancels it. Your video stays safe.")
                                    .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: "Keep exporting", action: departure.keepWorking)
                                ActionButton(title: "Stop export", primary: false, action: departure.stop)
                            }.padding(22).frame(maxWidth: 360)
                                .background { StageSurface(tone: .velvet) }.padding(20)
                                .frame(maxWidth: .infinity, minHeight: container.size.height)
                        }.background(.black.opacity(0.7))
                            .accessibilityAddTraits(.isModal)
                    }
                }
            }
    }
}

struct DownloadCompletionNotice: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Group {
            if offline.completedDownloadID != nil {
                HStack(spacing: 12) {
                    LocalizedText("Downloaded. Watch offline in Library.")
                        .font(.stage(.caption)).fixedSize(horizontal: false, vertical: true)
                    Button("View") {
                        offline.completedDownloadID = nil
                        library.openDownloads()
                    }.buttonStyle(CompactActionStyle())
                    IconButton(symbol: .close, label: "Dismiss message") { offline.completedDownloadID = nil }
                }.padding(12).foregroundStyle(TrickoStyle.paper)
                    .background { StageSurface(tone: .velvet) }
                    .padding(.horizontal, 12)
            }
        }.task(id: offline.completedDownloadID) {
            guard let notice = offline.completedDownloadID else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if offline.completedDownloadID == notice { offline.completedDownloadID = nil }
        }
    }
}

private struct OfflineExportButton: View {
    let clip: LessonClip
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    @State private var preparingSource = false
    @State private var exportTask: Task<Void, Never>?
    @State private var sharing: SharedFile?
    @State private var exportError: String?
    @State private var exportedFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(title: preparingSource ? "Preparing export…" : exportTask == nil ? "Export video" : "Exporting…",
                         primary: false, busy: exportTask != nil, action: startExport)
                .accessibilityIdentifier("player.exportVideo")
            if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil {
                LocalizedText("We download the video before exporting. Existing downloads are reused.")
                    .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                DownloadAllowanceSummary()
            }
            if preparingSource, offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.stage(.caption))
            }
            if exportTask != nil {
                Button("Cancel export") { departure.request() }.buttonStyle(CompactActionStyle())
            }
            if let exportError { ErrorNote(message: exportError) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
        .onDisappear { exportTask?.cancel() }
    }

    private func startExport() {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia else { downloadGate = true; return }
        if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil,
           !quota.mayDownload(clip.id, premium: commerce.premium) {
            downloadGate = true
            return
        }
        if let exportedFile, FileManager.default.fileExists(atPath: exportedFile.path) {
            sharing = SharedFile(url: exportedFile); return
        }
        exportError = nil
        exportTask = Task { @MainActor in
            defer { exportTask = nil; preparingSource = false; departure.finish() }
            var ownsDownload = false
            var converted: URL?
            defer { if let converted { try? FileManager.default.removeItem(at: converted) } }
            do {
                try commerce.requireMediaExport()
                var source = clip.playbackURL
                if !source.isFileURL || offline.cached(clip.id)?.isHLS == true {
                    preparingSource = true
                    if offline.downloadingID == clip.id {
                        for await downloadID in offline.$downloadingID.values {
                            try Task.checkCancellation()
                            if downloadID != clip.id { break }
                        }
                    }
                    try Task.checkCancellation()
                    if offline.cached(clip.id)?.isHLS != false, offline.downloadingID != clip.id {
                        guard !offline.busy else { throw TrickoError.service("Another download is in progress.") }
                        ownsDownload = true
                        await offline.download(clip, forExport: true)
                    }
                    for await downloadID in offline.$downloadingID.values {
                        try Task.checkCancellation()
                        if let cached = offline.cached(clip.id), !cached.isHLS { source = cached.url; break }
                        guard downloadID == clip.id else {
                            throw TrickoError.service(offline.error ?? "Download failed. No download allowance was used.")
                        }
                    }
                    try Task.checkCancellation()
                    guard source.isFileURL else { throw TrickoError.storage }
                    preparingSource = false
                }
                var output = source
                if !["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) {
                    let asset = AVURLAsset(url: source)
                    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
                          session.supportedFileTypes.contains(.mp4) else {
                        throw TrickoError.service("This video format cannot be exported. Please use an MP4 or MOV file.")
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                    converted = destination
                    session.outputURL = destination
                    session.outputFileType = .mp4
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { continuation in
                            session.exportAsynchronously { continuation.resume() }
                        }
                    } onCancel: { session.cancelExport() }
                    try Task.checkCancellation()
                    guard session.status == .completed else {
                        throw TrickoError.service("Video export failed. Please try again.")
                    }
                    output = destination
                }
                try Task.checkCancellation()
                try commerce.requireMediaExport()
                let recording = try await library.importMovie(output, exported: true, title: clip.title)
                let url = try await library.shareFile(for: recording, commerce: commerce)
                exportedFile = url
                if !Task.isCancelled { sharing = SharedFile(url: url) }
            } catch is CancellationError {
                if ownsDownload, offline.downloadingID == clip.id { await offline.cancel() }
            }
            catch {
                exportError = error.localizedDescription
            }
        }
        departure.begin { exportTask?.cancel() }
    }
}

struct DownloadAllowanceSummary: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Downloads left").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
            LocalizedText(api.session == nil ? "Connect to refresh your allowance." :
                            commerce.premium || quota.downloadsUnlimited ? "Unlimited" :
                            quota.usage == nil ? "Checking your limits…" : "\(quota.downloadsLeft) downloads left today")
                .font(.stage(.subheadline, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if quota.usage != nil, !commerce.premium { AllowanceResetText() }
            if quota.canRequestReward(for: .download, premium: commerce.premium) {
                ActionButton(title: "Download options", primary: false) { showingReward = true }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background { StageSurface(tone: .velvet) }
            .accessibilityElement(children: .contain)
            .onAppear { quota.resetIfNeeded() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
            .sheet(isPresented: $showingReward) { MembershipView(rewardKind: .download) }
    }
}
