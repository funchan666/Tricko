import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    let openAccount: () -> Void
    let openVideo: (PracticeRecording) -> Void
    let showImports: () -> Void
    @Binding var link: String
    @Binding var channel: ChannelRoute?
    @Binding var searchRequest: LessonSearch?
    @State private var error: String?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingRecentLinks = true
    @State private var showingLinkHistory = false
    @State private var pendingHistoryLink: String?
    @State private var showingCollections = true
    @State private var loadingCollections = true
    @State private var composerError: String?
    @State private var reviewingVideo: PracticeRecording?
    @FocusState private var focused: Bool

    var body: some View {
        homePage
            .fullScreenCover(isPresented: $showingLinkHistory, onDismiss: openSelectedHistoryLink) { linkHistoryPage }
            .fullScreenCover(isPresented: $paywall) { MembershipView() }
            .fullScreenCover(item: $reviewingVideo) { VideoReviewView(movie: $0) }
    }

    private var homePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        playerHeading.fixedSize()
                        Spacer(minLength: 0)
                        headerActions.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        playerHeading
                        headerActions
                    }
                }
                linkComposer
                localVideoSection
                browseVideosButton
                lessonResources
            }
            .trickoPage()
        }
        .foregroundStyle(TrickoStyle.paper)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
        .trickoScreenBackground()
    }

    private var playerHeading: some View {
        LocalizedText("Player")
            .font(.stage(.largeTitle, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerActions: some View {
        TrickoGlassGroup {
            HStack(spacing: 10) {
                PlusEntryButton(active: commerce.premium, compact: true) { paywall = true }
                accountButton
            }
        }
    }

    private var accountButton: some View {
        Button(action: openAccount) {
            Image("TabMe").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(TrickoStyle.paper)
                .accessibilityHidden(true)
                .frame(width: 44, height: 44)
                .trickoGlass(in: Circle())
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: L10n.text("Open Me and account settings", language: AppLanguage.from(locale))))
            .accessibilityIdentifier("home.account")
    }

    private var localVideoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            videoImport
            continueReview
            recentVideos
        }
    }

    private var videoImport: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Import a video")
                .font(.stage(.title2, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            LocalVideoImportButtons(prominent: true, onImport: openVideo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var continueReview: some View {
        let recent = library.movies.compactMap { movie in
            movie.latestPendingReviewPoint.map { (movie: movie, point: $0) }
        }.max { $0.point.updatedAt < $1.point.updatedAt }
        if let recent {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let count = recent.movie.pendingReviewCount.formatted(.number.locale(locale))
            let pending = L10n.format("%@ pending review", [count], language: AppLanguage.from(locale))
            Button { openReview(recent.movie) } label: {
                HStack(spacing: 12) {
                    if !typeSize.isAccessibilitySize {
                        LocalVideoCover(url: library.url(for: recent.movie), cornerRadius: 9, maximumPixelSize: 208)
                            .frame(width: 64, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedText("Continue review").font(.stage(.headline, weight: .semibold))
                        Text(verbatim: recent.movie.title)
                            .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CountBadge(text: count).accessibilityHidden(true)
                    Glyph(symbol: .back, size: 10, tint: TrickoStyle.coolAccent).rotationEffect(.degrees(180))
                }
                .padding(12)
                .frame(minHeight: 60)
                .trickoGlass(in: shape)
                .contentShape(.interaction, shape)
            }
            .buttonStyle(PressStyle())
            .accessibilityValue(Text(verbatim: pending))
        }
    }

    @ViewBuilder private var recentVideos: some View {
        let videos = Array(library.movies.lazy.filter { !$0.isExport }.prefix(3))
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        recentVideosTitle
                        Spacer(minLength: 12)
                        allVideosButton.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        recentVideosTitle
                        allVideosButton
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(videos) { movie in
                            recentVideo(movie)
                                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                                    let preferredWidth = typeSize.isAccessibilitySize ? 286 : min(230, max(150, width * 0.55))
                                    return min(width, preferredWidth)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        } else {
            inlineEmptyState("No imported videos yet", symbol: .feed)
        }
    }

    private func inlineEmptyState(_ title: String, symbol: TrickoGlyph) -> some View {
        HStack(spacing: 10) {
            StageStateSymbol(symbol: symbol, size: 32)
            LocalizedText(title)
                .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentVideo(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openVideo(movie) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    LocalVideoCover(url: library.url(for: movie), cornerRadius: 10, maximumPixelSize: 640)
                        .aspectRatio(1.6, contentMode: .fit)
                    Text(verbatim: movie.title).font(.stage(.subheadline, weight: .semibold))
                        .lineLimit(2).truncationMode(.middle)
                    LocalizedDateText(date: movie.date).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint(LocalizedStringKey("Full editor"))

            VideoReviewButton(movie: movie) { openReview(movie) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { StageSurface(tone: .smoke) }
    }

    private func openReview(_ movie: PracticeRecording) {
        focused = false
        reviewingVideo = movie
    }

    private var recentVideosTitle: some View {
        LocalizedText("Recent imports").font(.stage(.headline))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var allVideosButton: some View {
        Button(action: showImports) {
            HStack(spacing: 7) {
                LocalizedText("View all").font(.stage(.subheadline, weight: .semibold))
                Glyph(symbol: .back, size: 9, tint: TrickoStyle.coolAccent).rotationEffect(.degrees(180))
            }
            .foregroundStyle(TrickoStyle.coolAccent).frame(minHeight: 44)
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var browseVideosButton: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard searchRequest == nil else { return }
            focused = false
            searchRequest = LessonSearch(query: "")
        } label: {
            HStack(spacing: 14) {
                Glyph(symbol: .play, size: 16, tint: TrickoStyle.ink)
                    .frame(width: 36, height: 36)
                    .background(TrickoStyle.coolAccent, in: Circle())
                LocalizedText("Browse videos")
                    .font(.stage(.headline, weight: .semibold))
                    .foregroundStyle(TrickoStyle.paper)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 12, tint: TrickoStyle.coolAccent)
                    .rotationEffect(.degrees(180))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .trickoGlass(in: shape, tint: TrickoStyle.coolAccent.opacity(0.12))
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .disabled(searchRequest != nil)
        .accessibilityIdentifier("home.watchLessons")
    }

    private var linkHistory: [LessonLinkVisit] {
        library.history.filter { $0.link.nilIfBlank != nil }
    }

    @ViewBuilder private var lessonResources: some View {
        let visits = linkHistory
        let hasCollections = !(commerce.release?.lcList?["us"] ?? []).isEmpty
        if !visits.isEmpty || hasCollections {
            VStack(alignment: .leading, spacing: 4) {
                if !visits.isEmpty {
                    lessonDisclosure("Recently opened", symbol: .link, expanded: showingRecentLinks) {
                        showingRecentLinks.toggle()
                    }
                    if showingRecentLinks { recentLinks(visits) }
                }
                if hasCollections {
                    lessonDisclosure("Video collections", symbol: .folder, expanded: showingCollections) {
                        if !showingCollections {
                            channels = []
                            error = nil
                            loadingCollections = true
                        }
                        showingCollections.toggle()
                    }
                    if showingCollections { collections }
                }
            }
        }
    }

    private func lessonDisclosure(
        _ title: String, symbol: TrickoGlyph, expanded: Bool, action: @escaping () -> Void
    ) -> some View {
        let arrowAngle: Double = expanded ? (direction == .rightToLeft ? 90 : -90) : 180
        return Button(action: action) {
            HStack(spacing: 10) {
                Glyph(symbol: symbol, size: 16, tint: TrickoStyle.coolAccent)
                LocalizedText(title).font(.stage(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 10, tint: TrickoStyle.secondary)
                    .rotationEffect(.degrees(arrowAngle))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(expanded ? .isSelected : [])
    }

    private var collections: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        return VStack(alignment: .leading, spacing: 12) {
            if let error {
                MessagePanel(title: "Couldn’t load collections", message: error, actionTitle: "Try again") { channelRetry += 1 }
            } else if channels.isEmpty {
                if loadingCollections {
                    StageLoadingIndicator(title: "Loading…", compact: true)
                } else {
                    inlineEmptyState("No video collections yet.", symbol: .library)
                }
            } else {
                lessonIndex
            }
        }
        .padding(.vertical, 8)
        .task(id: request) {
            guard !Task.isCancelled, !request.links.isEmpty else { return }
            loadingCollections = true
            channels = []
            error = nil
            defer { if !Task.isCancelled { loadingCollections = false } }
            do {
                let result = try await api.channels(links: request.links)
                if !Task.isCancelled {
                    channels = result.filter { $0.extraInfo?.channelName != nil && $0.extraInfo?.externalLinks != nil }
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var lessonIndex: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(channels.indices, id: \.self) { index in
                    let item = channels[index]
                    if let info = item.extraInfo, let title = info.channelName, let short = info.externalLinks {
                        Button { channel = ChannelRoute(link: short, title: title) } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: title).font(.stage(.title3, display: true))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let count = info.videoFileCount {
                                        LocalizedText("\(count) videos").font(.stage(.caption))
                                            .foregroundStyle(TrickoStyle.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                MediaCover(url: WebAddress.media(item.shortCover))
                                    .frame(width: 56, height: 48).clipShape(.rect(cornerRadius: 5))
                                    .accessibilityHidden(true)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                        Divider().overlay(TrickoStyle.line)
                    }
                }
            }
        }
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrickoGlassGroup {
                HStack(spacing: 8) {
                    linkField
                    openLessonButton
                }
            }
            if let composerError { ErrorNote(message: composerError) }
            pasteButton
        }
        .onChange(of: link) { _, _ in composerError = nil }
    }

    private var openLessonButton: some View {
        Button(action: resolve) {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            let label = Glyph(symbol: .search, size: 20, tint: canOpenLink ? TrickoStyle.coolAccent : TrickoStyle.secondary)
                .frame(width: 52, height: 52)
            label.trickoGlass(in: shape, tint: canOpenLink ? TrickoStyle.coolAccent.opacity(0.25) : nil)
                .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle(disabledOpacity: 1))
        .disabled(!canOpenLink)
        .accessibilityLabel(Text(verbatim: L10n.text("Find video", language: AppLanguage.from(locale))))
        .accessibilityIdentifier("home.openLesson")
    }

    private var linkField: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let prompt = Text(verbatim: L10n.text("Search", language: AppLanguage.from(locale)))
            .foregroundStyle(TrickoStyle.secondary)
        return HStack(spacing: 10) {
            Glyph(symbol: .link, size: 18, tint: TrickoStyle.coolAccent)
            TextField("", text: $link, prompt: prompt)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { resolve() }
                .focused($focused).font(.stage(.body)).foregroundStyle(TrickoStyle.paper)
                .tint(TrickoStyle.coolAccent)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(LocalizedStringKey("Search"))
                .accessibilityIdentifier("home.lessonLinkField")
            if !link.isEmpty {
                Button {
                    link = ""
                    composerError = nil
                    focused = true
                } label: {
                    Glyph(symbol: .close, size: 13, tint: TrickoStyle.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(PressStyle())
                    .accessibilityLabel(LocalizedStringKey("Clear link"))
                    .accessibilityIdentifier("home.clearLink")
            }
        }
            .padding(.leading, 14).padding(.trailing, link.isEmpty ? 14 : 4)
            .trickoGlass(in: shape, interactive: false)
            .overlay {
                shape.strokeBorder(focused ? TrickoStyle.coolAccent : .clear, lineWidth: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .keyboardInputRegion("home-link-input")
    }

    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    private var pasteButton: some View {
        Button(action: pasteCopiedLink) { LocalizedText("Paste") }
            .buttonStyle(EmptyStateActionStyle(primary: false, minHeight: 44, horizontalPadding: 12))
            .accessibilityIdentifier("home.pasteLink")
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string, text.nilIfBlank != nil else {
            composerError = "No text to paste."
            return
        }
        composerError = nil
        link = text
    }
    private func recentLinks(_ visits: [LessonLinkVisit]) -> some View {
        let preview = visits.prefix(3)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(preview) { visit in
                historyLinkRow(visit) { openHistoryLink(visit.link) }
            }
            if preview.count < visits.count {
                Button {
                    focused = false
                    showingLinkHistory = true
                } label: {
                    LocalizedText("View more")
                }
                .buttonStyle(EmptyStateActionStyle(primary: false))
                .disabled(searchRequest != nil)
                .accessibilityIdentifier("home.viewMoreHistory")
            } else {
                clearHistoryButton
            }
        }
    }

    private var linkHistoryPage: some View {
        let visits = linkHistory
        let days = Dictionary(grouping: visits) { calendar.startOfDay(for: $0.date) }
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        Section {
                            ForEach(days[day] ?? []) { visit in
                                historyLinkRow(visit) {
                                    pendingHistoryLink = visit.link
                                    showingLinkHistory = false
                                }
                                .padding(.bottom, 6)
                                .overlay(alignment: .bottom) { Divider().overlay(TrickoStyle.line) }
                            }
                        } header: {
                            LocalizedDateText(date: day)
                                .font(.stage(.subheadline, weight: .semibold))
                                .foregroundStyle(TrickoStyle.coolAccent)
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }.trickoPage()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !visits.isEmpty { clearHistoryButton.padding(.vertical, 8) }
            }
            .trickoScreenBackground()
            .navigationTitle(Text(verbatim: L10n.text("Recently opened", language: AppLanguage.from(locale))))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLinkHistory = false } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
        .foregroundStyle(TrickoStyle.paper)
        .onChange(of: visits.isEmpty) { _, isEmpty in
            if isEmpty { showingLinkHistory = false }
        }
    }

    private func historyLinkRow(_ visit: LessonLinkVisit, open: @escaping () -> Void) -> some View {
        HStack {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: visit.title).font(.stage(.headline)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Text(verbatim: visit.link).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(searchRequest != nil || pendingHistoryLink != nil)
            IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
        }
    }

    private var clearHistoryButton: some View {
        Button(action: library.clearHistory) { LocalizedText("Clear history") }
            .buttonStyle(EmptyStateActionStyle(primary: false))
    }

    private func openSelectedHistoryLink() {
        guard let pendingHistoryLink else { return }
        self.pendingHistoryLink = nil
        openHistoryLink(pendingHistoryLink)
    }

    private func openHistoryLink(_ target: String) {
        guard searchRequest == nil else { return }
        link = target
        resolve()
    }

    private func resolve() {
        guard let text = link.nilIfBlank, searchRequest == nil else { return }
        focused = false
        composerError = nil
        searchRequest = LessonSearch(query: text)
    }
}

struct LessonSearch: Identifiable {
    let id = UUID()
    let query: String
}

private struct ChannelRequest: Equatable {
    let links: [String]
    let attempt: Int
}

struct ChannelView: View {
    @Environment(\.dismiss) private var dismiss
    let route: ChannelRoute
    @State private var folders: [ChannelRoute] = []

    var body: some View {
        NavigationStack(path: $folders) {
            ChannelDirectory(route: route, back: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                    }
                }
                .navigationDestination(for: ChannelRoute.self) { child in
                    ChannelDirectory(route: child, back: {
                        if !folders.isEmpty { folders.removeLast() }
                    })
                }
        }
        .trickoImmersiveChrome()
    }
}

private struct ChannelDirectory: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dynamicTypeSize) private var typeSize
    let route: ChannelRoute
    let back: () -> Void
    @State private var items: [RemoteLessonFile] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var player: PlayerRoute?
    var body: some View {
        ScrollView {
            if items.isEmpty {
                channelStatus.trickoPage()
            } else {
                channelList.trickoPage()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { DownloadCompletionNotice() }
        .trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
        .navigationTitle(Text(verbatim: route.title))
        .navigationBarTitleDisplayMode(.large)
        .task { if items.isEmpty && !loaded { await load() } }
        .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
    }

    @ViewBuilder private var channelStatus: some View {
        if loading || (!loaded && error == nil) {
            StageLoadingIndicator(title: "Loading videos…")
                .frame(maxWidth: .infinity)
        } else {
            EmptyStatePanel(symbol: .feed) {
                if let error {
                    EmptyStateCopy(title: "Couldn’t load videos", message: error)
                    Button { Task { await load() } } label: { LocalizedText("Try again") }
                        .buttonStyle(EmptyStateActionStyle(primary: false))
                } else {
                    EmptyStateCopy(title: "No videos to show", message: "This channel has no available videos.")
                    if hasMore {
                        Button { Task { await load() } } label: { LocalizedText("Load more") }
                            .buttonStyle(EmptyStateActionStyle(primary: false))
                    } else {
                        Button(action: back) { LocalizedText("Back") }
                            .buttonStyle(EmptyStateActionStyle(primary: false, symbol: .back))
                    }
                }
            }
        }
    }

    private var channelList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.stableID) { item in
                if item.isFolder == true, let link = item.landingPage?.nilIfBlank {
                    NavigationLink(value: ChannelRoute(link: link, title: item.name ?? L10n.text("Folder"))) {
                        channelRow(item)
                    }
                } else {
                    Button { open(item) } label: { channelRow(item) }
                }
                Divider().overlay(TrickoStyle.line)
            }
            if let error { ErrorNote(message: error) }
            if hasMore {
                ActionButton(title: error == nil ? "Load more" : "Try again", primary: false,
                             busy: loading, busyTitle: "Loading…") { Task { await load() } }
            }
        }
        .buttonStyle(PressStyle())
    }

    private func channelRow(_ item: RemoteLessonFile) -> some View {
        let folder = item.isFolder == true
        return HStack(spacing: 14) {
            if !typeSize.isAccessibilitySize {
                MediaCover(url: WebAddress.media(item.coverImage), folder: folder)
                    .frame(width: 78, height: 54).clipShape(.rect(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: item.name ?? L10n.text("Untitled"))
                    .font(.stage(.headline)).fixedSize(horizontal: false, vertical: true)
                LocalizedText(folder ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                    .font(.stage(.caption).monospacedDigit()).foregroundStyle(TrickoStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Glyph(symbol: folder ? .back : .play, size: folder ? 12 : 17, tint: TrickoStyle.coolAccent)
                .rotationEffect(.degrees(folder ? 180 : 0))
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.channelPage(link: route.link, page: page)
            try Task.checkCancellation()
            var seen = Set(items.map(\.stableID))
            items += result.list.filter { $0.name?.nilIfBlank != nil && !$0.stableID.isEmpty && seen.insert($0.stableID).inserted }
            hasMore = page * 20 < result.total && !result.list.isEmpty
            page += 1
            loaded = true
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func open(_ item: RemoteLessonFile) {
        if let clip = item.clip(channel: route.title) {
            player = PlayerRoute(clips: items.compactMap { $0.clip(channel: route.title) }, startID: clip.id, continuesRecommendations: true)
        } else { error = "This item does not contain a playable video." }
    }
}
