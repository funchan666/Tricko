import Accessibility
import AVFoundation
import SwiftUI

struct VideoReviewRoute: Identifiable {
    let movie: PracticeRecording
    let startingAt: Double?
    var id: UUID { movie.id }
}

struct VideoReviewButton: View {
    @Environment(\.locale) private var locale
    let movie: PracticeRecording
    let action: () -> Void

    var body: some View {
        let count = movie.pendingReviewCount
        let countText = count.formatted(.number.locale(locale))
        let pendingDescription = count > 0
            ? L10n.format("%@ pending review", [countText], language: AppLanguage.from(locale))
            : nil
        HStack(spacing: 6) {
            Button(action: action) { LocalizedText("Review video") }
                .buttonStyle(EmptyStateActionStyle(primary: false, symbol: .bookmark, minHeight: 44, horizontalPadding: 10))
                .accessibilityValue(Text(verbatim: pendingDescription.map { "\(movie.title), \($0)" } ?? movie.title))
            if count > 0 {
                CountBadge(text: countText)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct VideoReviewView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlaybackController()
    @State private var aspectRatio: CGFloat = 16.0 / 9.0
    @State private var unavailable = false
    @State private var activePointID: UUID?
    @State private var selectedMarkerFilter: MarkerFilter?
    @State private var finishedPendingReview = false
    @State private var draft: VideoReviewPoint?
    @State private var saveError: String?
    let movie: PracticeRecording
    var startingAt: Double? = nil

    private enum Section: Hashable {
        case draft
        case marker(UUID)
    }

    private enum MarkerFilter: String, CaseIterable {
        case pending = "Pending review"
        case all = "All"
    }

    private static let completionMessage = "All markers reviewed."

    private var points: [VideoReviewPoint] {
        let saved = library.movies.first { $0.id == movie.id }?.reviewPoints ?? []
        return saved.sorted {
            if $0.seconds == $1.seconds { return $0.updatedAt < $1.updatedAt }
            return $0.seconds < $1.seconds
        }
    }

    private var canMark: Bool {
        !playback.isLoading && !playback.isSeeking && playback.error == nil &&
        playback.player.currentItem?.status == .readyToPlay
    }

    private var canJumpToMarker: Bool {
        !unavailable && !playback.isLoading && playback.error == nil
    }

    var body: some View {
        let points = self.points
        let pendingPoints = points.filter(\.isPendingReview)
        let filter = markerFilter(for: pendingPoints)
        let activePoint = points.first { $0.id == activePointID }
        VStack(spacing: 0) {
            SheetHeading(title: "Video review") { dismiss() }
            if let draft {
                draftWorkspace(draft)
            } else {
                reviewWorkspace(points: points, pendingPoints: pendingPoints, filter: filter, activePoint: activePoint)
            }
        }
        .trickoScreenBackground()
        .foregroundStyle(TrickoStyle.paper)
        .interactiveDismissDisabled(draft != nil)
        .task(id: movie.id) { await openVideo() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.pause() } }
        .onDisappear { playback.release() }
    }

    private func reviewWorkspace(
        points: [VideoReviewPoint],
        pendingPoints: [VideoReviewPoint],
        filter: MarkerFilter,
        activePoint: VideoReviewPoint?
    ) -> some View {
        GeometryReader { viewport in
            let shortViewport = viewport.size.height < 460
            let sideBySide = viewport.size.width >= 520 && shortViewport
            let compact = shortViewport || typeSize.isAccessibilitySize
            let videoFraction: CGFloat = sideBySide ? 0.4 : (compact ? 0.22 : 0.32)
            let videoHeight = min(320, viewport.size.height * videoFraction)
            let layout = sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))

            layout {
                VStack(alignment: .leading, spacing: 8) {
                    if !shortViewport {
                        Text(verbatim: movie.title)
                            .font(.stage(.headline, weight: .semibold))
                            .lineLimit(1)
                    }
                    playerTray(maxVideoHeight: videoHeight, compactControls: compact)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: sideBySide ? viewport.size.width * 0.47 : nil, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    reviewMarkerLists(points: points, pendingPoints: pendingPoints, filter: filter, compact: compact)
                    reviewFooter(activePoint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .trickoPage()
    }

    private func reviewMarkerLists(
        points: [VideoReviewPoint],
        pendingPoints: [VideoReviewPoint],
        filter: MarkerFilter,
        compact: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(MarkerFilter.allCases, id: \.rawValue) { listFilter in
                let isVisible = listFilter == filter
                VStack(alignment: .leading, spacing: 8) {
                    if listFilter == .pending && !pendingPoints.isEmpty {
                        pendingNavigation(in: points, pendingPoints: pendingPoints, compact: compact)
                    }
                    if !points.isEmpty {
                        markerFilters(totalCount: points.count, pendingCount: pendingPoints.count, filter: listFilter)
                    }
                    reviewMarkerList(listFilter == .pending ? pendingPoints : points,
                                     hasMarkers: !points.isEmpty, isVisible: isVisible)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
            }
        }
    }

    private func reviewMarkerList(
        _ visiblePoints: [VideoReviewPoint],
        hasMarkers: Bool,
        isVisible: Bool
    ) -> some View {
        ScrollViewReader { listScroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visiblePoints.isEmpty && !finishedPendingReview {
                        LocalizedText(hasMarkers ? Self.completionMessage : "Mark a moment to revisit it later.")
                            .font(.stage(.subheadline))
                            .foregroundStyle(TrickoStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(visiblePoints) { point in
                        VStack(spacing: 0) {
                            Rectangle().fill(TrickoStyle.line).frame(height: 1).accessibilityHidden(true)
                            markerRow(point, isCurrent: point.id == activePointID) { seek(to: point) }
                        }
                        .id(Section.marker(point.id))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: activePointID, initial: true) { _, id in
                guard isVisible, let id, visiblePoints.contains(where: { $0.id == id }) else { return }
                listScroll.scrollTo(Section.marker(id), anchor: nil)
            }
        }
        .frame(minHeight: 44, maxHeight: .infinity)
    }

    private func reviewFooter(_ activePoint: VideoReviewPoint?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if finishedPendingReview {
                HStack(spacing: 8) {
                    Glyph(symbol: .saved, size: 17, tint: TrickoStyle.coolAccent)
                    LocalizedText(Self.completionMessage)
                        .font(.stage(.subheadline, weight: .semibold))
                        .foregroundStyle(TrickoStyle.coolAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let saveError { ErrorNote(message: saveError) }
            if let activePoint {
                HStack(spacing: 8) {
                    IconButton(symbol: .bookmark, label: "Mark this moment", action: markMoment)
                        .trickoGlass(in: Circle())
                        .disabled(!canMark)
                    reviewStatusButton(activePoint)
                }
            } else {
                ActionButton(title: "Mark this moment", action: markMoment)
                    .disabled(!canMark)
            }
        }
    }

    private func draftWorkspace(_ draft: VideoReviewPoint) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: movie.title)
                        .font(.stage(.headline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    playerTray()
                    pointEditor(draft).id(Section.draft)
                }
                .trickoPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.id, initial: true) { _, _ in
                scroll.scrollTo(Section.draft, anchor: .bottom)
            }
        }
    }

    private func playerTray(maxVideoHeight: CGFloat = 320, compactControls: Bool = false) -> some View {
        VStack(spacing: 0) {
            VideoSurface(player: playback.player, fill: false)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: min(540, maxVideoHeight * aspectRatio))
                .frame(maxWidth: .infinity)
                .background(.black)
                .overlay {
                    if playback.isLoading && !unavailable {
                        AccountLoadingIndicator(title: "Preparing your video…")
                    }
                }
            if unavailable || playback.error != nil {
                ErrorNote(message: "This video is unavailable for review.")
                    .padding(.horizontal, 12)
            } else {
                EditorPlaybackBar(playback: playback, timeline: playback.timeline,
                                  disabled: playback.isLoading, compact: compactControls)
                    .padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .background(TrickoStyle.surface)
        .clipShape(.rect(cornerRadius: 18))
    }

    private func markerFilters(totalCount: Int, pendingCount: Int, filter: MarkerFilter) -> some View {
        let counts = [MarkerFilter.pending.rawValue: pendingCount, MarkerFilter.all.rawValue: totalCount]
        return StageFilter(values: MarkerFilter.allCases.map(\.rawValue), selected: filter.rawValue, counts: counts) {
            selectedMarkerFilter = MarkerFilter(rawValue: $0)
        }
    }

    private func markerFilter(for pendingPoints: [VideoReviewPoint]) -> MarkerFilter {
        selectedMarkerFilter ?? (pendingPoints.isEmpty ? .all : .pending)
    }

    private func pendingNavigation(
        in points: [VideoReviewPoint],
        pendingPoints: [VideoReviewPoint],
        compact: Bool
    ) -> some View {
        let index = points.firstIndex { $0.id == activePointID }
        let previous = index.flatMap { points.prefix($0).last(where: \.isPendingReview) }
        let next = points.dropFirst(index.map { $0 + 1 } ?? 0).first(where: \.isPendingReview)
        let pendingIndex = pendingPoints.firstIndex { $0.id == activePointID }
        return HStack(spacing: 8) {
            markerNavigationButton("Previous marker", point: previous, forward: false, compact: compact)
            if compact { Spacer(minLength: 0) }
            if let pendingIndex {
                let current = (pendingIndex + 1).formatted(.number.locale(locale))
                let total = pendingPoints.count.formatted(.number.locale(locale))
                let label = L10n.format("Marker %@ of %@", [current, total], language: AppLanguage.from(locale))
                CountBadge(text: "\(current) / \(total)")
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(Text(verbatim: label))
            }
            if compact { Spacer(minLength: 0) }
            markerNavigationButton("Next marker", point: next, forward: true, compact: compact)
        }
        .disabled(!canJumpToMarker)
    }

    private func markerNavigationButton(
        _ title: String,
        point: VideoReviewPoint?,
        forward: Bool,
        compact: Bool
    ) -> some View {
        let jump = { if let point { seek(to: point) } }
        return Group {
            if compact {
                IconButton(symbol: .back, label: title, action: jump)
                    .rotationEffect(.degrees(forward ? 180 : 0))
                    .trickoGlass(in: Circle())
            } else {
                ActionButton(title: title, primary: false, action: jump)
            }
        }
        .disabled(point == nil)
    }

    private func reviewStatusButton(_ point: VideoReviewPoint) -> some View {
        ActionButton(title: point.isPendingReview ? "Mark as reviewed" : "Reopen marker", primary: false) {
            updateReviewStatus(point)
        }
    }

    private func updateReviewStatus(_ point: VideoReviewPoint) {
        let points = self.points
        guard activePointID == point.id, var updated = points.first(where: { $0.id == point.id }),
              updated.isPendingReview == point.isPendingReview else { return }
        let pendingPoints = points.filter(\.isPendingReview)
        let filter = markerFilter(for: pendingPoints)
        updated.reviewedAt = point.isPendingReview ? .now : nil
        guard persist(updated) else { return }
        finishedPendingReview = false

        guard point.isPendingReview, filter == .pending,
              let index = pendingPoints.firstIndex(where: { $0.id == point.id }) else { return }
        if let next = pendingPoints.dropFirst(index + 1).first ?? pendingPoints.prefix(index).first {
            seek(to: next)
        } else {
            finishedPendingReview = true
            AccessibilityNotification.Announcement(
                L10n.text(Self.completionMessage, language: AppLanguage.from(locale))
            ).post()
        }
    }

    private func markerRow(_ point: VideoReviewPoint, isCurrent: Bool, jump: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: jump) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: timecode(point.seconds))
                        .font(.stage(.subheadline, weight: isCurrent ? .bold : .semibold).monospacedDigit())
                        .foregroundStyle(TrickoStyle.accent)
                        .environment(\.layoutDirection, .leftToRight)
                    if let category = point.category {
                        LocalizedText(category.label).font(.stage(.subheadline, weight: .semibold))
                    }
                    if !point.note.isEmpty {
                        Text(verbatim: point.note)
                            .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                            .lineLimit(3)
                    }
                    if !point.isPendingReview {
                        LocalizedText("Reviewed")
                            .font(.stage(.caption, weight: .medium))
                            .foregroundStyle(TrickoStyle.coolAccent)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .disabled(!canJumpToMarker)
            IconButton(symbol: .edit, label: "Edit marker") {
                seek(to: point)
                draft = point
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 8)
        .background {
            if isCurrent {
                StageSurface(tone: .velvet, radius: 12, border: TrickoStyle.accent.opacity(0.45))
                    .padding(.vertical, 2)
            }
        }
        .disabled(draft != nil)
    }

    private func pointEditor(_ point: VideoReviewPoint) -> some View {
        let note = Binding(get: { draft?.note ?? "" }, set: { draft?.note = $0 })
        let hasSavedPoint = points.contains { $0.id == point.id }
        let actions = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: timecode(point.seconds))
                .font(.stage(.title2, weight: .semibold).monospacedDigit())
                .foregroundStyle(TrickoStyle.accent)
                .environment(\.layoutDirection, .leftToRight)
            StageFilter(values: ["General note"] + VideoReviewCategory.allCases.map(\.label),
                        selected: point.category?.label ?? "General note") { label in
                draft?.category = VideoReviewCategory.allCases.first { $0.label == label }
            }
            TextField(L10n.text("Add a note (optional)", language: AppLanguage.from(locale)), text: note, axis: .vertical)
                .lineLimit(2...6)
                .modifier(FieldStyle())
            if let saveError { ErrorNote(message: saveError) }
            actions {
                ActionButton(title: "Cancel", primary: false, action: clearDraft)
                ActionButton(title: "Save", action: saveDraft)
            }
            if hasSavedPoint {
                Button(role: .destructive) { removePoint(point) } label: {
                    LocalizedText("Remove marker")
                        .font(.stage(.subheadline, weight: .semibold))
                        .foregroundStyle(TrickoStyle.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(14)
        .background { StageSurface(tone: .smoke, radius: 18) }
    }

    private func openVideo() async {
        guard !Task.isCancelled else { return }
        let url = library.url(for: movie)
        guard FileManager.default.fileExists(atPath: url.path) else {
            unavailable = true
            return
        }
        unavailable = false
        let asset = AVURLAsset(url: url)
        playback.load(AVPlayerItem(asset: asset), autoplay: false)
        let current = library.movies.first { $0.id == movie.id }
        if let seconds = startingAt {
            playback.seek(seconds)
        } else if let point = current?.latestPendingReviewPoint {
            seek(to: point)
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform), !Task.isCancelled {
            let bounds = CGRect(origin: .zero, size: size).applying(transform).standardized
            let ratio = bounds.width / bounds.height
            if ratio.isFinite, ratio > 0 { aspectRatio = min(3, max(0.4, ratio)) }
        }
    }

    private func markMoment() {
        guard canMark, let item = playback.player.currentItem else { return }
        playback.pause()
        let time = playback.player.currentTime().seconds
        let duration = item.duration.seconds
        guard time.isFinite, duration.isFinite, duration > 0 else { return }
        finishedPendingReview = false
        draft = VideoReviewPoint(seconds: max(0, min(time, duration)))
    }

    private func seek(to point: VideoReviewPoint) {
        playback.pause()
        playback.seek(point.seconds)
        activePointID = point.id
        finishedPendingReview = false
        saveError = nil
    }

    private func timecode(_ seconds: Double) -> String {
        let bounded = seconds.isFinite ? min(max(0, seconds), 359_999) : 0
        let tenths = Int(bounded * 10)
        return "\(durationLabel(Double(tenths / 10))).\(tenths % 10)"
    }

    private func saveDraft() {
        guard var point = draft else { return }
        point.note = point.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard persist(point) else { return }
        activePointID = point.id
        clearDraft()
    }

    @discardableResult
    private func persist(_ point: VideoReviewPoint) -> Bool {
        var point = point
        point.updatedAt = .now
        do {
            try library.saveReviewPoint(point, for: movie.id)
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func removePoint(_ point: VideoReviewPoint) {
        do {
            try library.removeReviewPoint(point.id, from: movie.id)
            activePointID = nil
            clearDraft()
        } catch { saveError = error.localizedDescription }
    }

    private func clearDraft() {
        draft = nil
        saveError = nil
    }
}
