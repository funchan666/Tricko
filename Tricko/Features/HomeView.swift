import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.locale) private var locale
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
    @State private var showingLinkGuide = false
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
            .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            .sheet(isPresented: $showingLinkHistory, onDismiss: openSelectedHistoryLink) { linkHistorySheet }
            .fullScreenCover(isPresented: $paywall) { MembershipView() }
            .sheet(item: $reviewingVideo) { VideoReviewView(movie: $0) }
    }

    private var homePage: some View {
        GeometryReader { viewport in
            let topInset = viewport.safeAreaInsets.top
            let photoHeight = min((viewport.size.height + topInset) * 0.42, 336)
            ScrollView {
                VStack(spacing: 0) {
                    headerActions
                        .trickoPage()
                        .frame(minHeight: max(0, photoHeight - topInset), alignment: .top)

                    VStack(alignment: .leading, spacing: 24) {
                        lessonAccess
                        localVideoSection
                        lessonResources
                    }
                    .trickoPage()
                    .background(TrickoStyle.background)
                }
                .foregroundStyle(TrickoStyle.paper)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
            .background {
                homePhoto
                    .frame(height: photoHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: [.top, .horizontal])
            }
        }
        .trickoScreenBackground()
    }

    private var homePhoto: some View {
        StagePhoto(asset: "VideoHomePhoto", alignment: .trailing)
            .environment(\.layoutDirection, .leftToRight)
            .overlay {
                LinearGradient(stops: [
                    .init(color: TrickoStyle.background.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.60),
                    .init(color: TrickoStyle.background.opacity(0.56), location: 0.84),
                    .init(color: TrickoStyle.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            PlusEntryButton(active: commerce.premium, compact: true) { paywall = true }
            accountButton
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
            HStack(spacing: 8) {
                Glyph(symbol: .feed, size: 15, tint: TrickoStyle.coolAccent)
                LocalizedText("No imported videos yet")
                    .font(.stage(.footnote))
                    .foregroundStyle(TrickoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private var lessonAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            linkComposer
            browseVideosButton
        }
    }

    private var browseVideosButton: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            guard searchRequest == nil else { return }
            focused = false
            searchRequest = LessonSearch(query: "")
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Watch lessons")
                        .font(.stage(.title3, weight: .bold))
                        .foregroundStyle(TrickoStyle.paper)
                    LocalizedText("No link needed")
                        .font(.stage(.footnote, weight: .medium))
                        .foregroundStyle(TrickoStyle.coolAccent)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Glyph(symbol: .play, size: 19, tint: TrickoStyle.accent)
                    .frame(width: 48, height: 48)
                    .trickoGlass(in: Circle())
                    .background(TrickoStyle.ink.opacity(0.78), in: Circle())
                    .allowsHitTesting(false)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 86)
            .background { browseVideosBackdrop.clipShape(shape) }
            .overlay {
                shape.strokeBorder(TrickoStyle.coolAccent.opacity(0.18))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .disabled(searchRequest != nil)
        .accessibilityIdentifier("home.watchLessons")
    }

    private var browseVideosBackdrop: some View {
        TrickoStyle.surface.overlay {
            StagePhoto(asset: "VideoBrowsePhoto")
                .overlay {
                    LinearGradient(stops: [
                        .init(color: TrickoStyle.ink.opacity(0.92), location: 0),
                        .init(color: TrickoStyle.ink.opacity(0.88), location: 0.46),
                        .init(color: TrickoStyle.ink.opacity(0.52), location: 0.70),
                        .init(color: TrickoStyle.ink.opacity(0.24), location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .environment(\.layoutDirection, .leftToRight)
                .scaleEffect(x: direction == .rightToLeft ? -1 : 1, y: 1)
                .opacity(typeSize.isAccessibilitySize ? 0.30 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    lessonDisclosure("Lesson collections", symbol: .folder, expanded: showingCollections) {
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
                MessagePanel(title: "Couldn’t load lesson collections", message: error, actionTitle: "Try again") { channelRetry += 1 }
            } else if channels.isEmpty {
                if loadingCollections {
                    AccountLoadingIndicator(title: "Loading…").frame(maxWidth: .infinity)
                } else {
                    LocalizedText("No lesson collections yet.").font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
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
            HStack(spacing: 8) {
                linkField
                openLessonButton
            }
            if let composerError { ErrorNote(message: composerError) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pasteButton.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    allowanceLabel.fixedSize(horizontal: true, vertical: false)
                    linkHelpButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    pasteButton
                    allowanceLabel
                    linkHelpButton
                }
            }
            LocalizedText("If no videos match, your input is sent to Google Search.")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: link) { _, _ in composerError = nil }
    }

    private var linkHelpButton: some View {
        Button {
            focused = false
            showingLinkGuide = true
        } label: {
            LocalizedText("How to").font(.stage(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.vertical, 8).frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(TrickoStyle.coolAccent)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.linkHelp")
    }

    private var openLessonButton: some View {
        Button(action: resolve) {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            let label = Glyph(symbol: .search, size: 20, tint: canOpenLink ? TrickoStyle.ink : TrickoStyle.secondary)
                .frame(width: 52, height: 52)
            Group {
                if canOpenLink { label.background(TrickoStyle.coolAccent, in: shape) }
                else { label.trickoGlass(in: shape) }
            }
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle(disabledOpacity: 1))
        .disabled(!canOpenLink)
        .accessibilityLabel(Text(verbatim: L10n.text("Open lesson", language: AppLanguage.from(locale))))
        .accessibilityIdentifier("home.openLesson")
    }

    private var linkField: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let prompt = Text(verbatim: L10n.text("Lesson link or short code", language: AppLanguage.from(locale)))
            .foregroundStyle(TrickoStyle.paperSecondary)
        return HStack(spacing: 10) {
            Glyph(symbol: .link, size: 16, tint: TrickoStyle.paperSecondary)
            TextField("", text: $link, prompt: prompt)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { resolve() }
                .focused($focused).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.ink)
                .tint(TrickoStyle.ink)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(LocalizedStringKey("Lesson link or short code"))
                .accessibilityIdentifier("home.lessonLinkField")
            if !link.isEmpty {
                Button {
                    link = ""
                    composerError = nil
                    focused = true
                } label: {
                    Glyph(symbol: .close, size: 13, tint: TrickoStyle.ink.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(PressStyle())
                    .accessibilityLabel(LocalizedStringKey("Clear link"))
                    .accessibilityIdentifier("home.clearLink")
            }
        }
            .padding(.leading, 14).padding(.trailing, link.isEmpty ? 14 : 4)
            .background(TrickoStyle.paper, in: shape)
            .overlay {
                shape.strokeBorder(focused ? TrickoStyle.coolAccent : .clear, lineWidth: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .environment(\.colorScheme, .light)
            .keyboardInputRegion("home-link-input")
    }

    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    @ViewBuilder private var allowanceLabel: some View {
        if api.session != nil {
            LocalizedText(commerce.premium ? "Unlimited" : quota.usage == nil ? "Checking your limits…"
                          : quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var pasteButton: some View {
        Button(action: pasteCopiedLink) { LocalizedText("Paste") }
            .buttonStyle(EmptyStateActionStyle(primary: false, minHeight: 44, horizontalPadding: 12))
            .accessibilityIdentifier("home.pasteLink")
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string, text.nilIfBlank != nil else {
            composerError = "Copy a lesson link or code, then tap Paste."
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

    private var linkHistorySheet: some View {
        let visits = linkHistory
        return VStack(alignment: .leading, spacing: 12) {
            StageSheetHeader(title: "Recently opened") { showingLinkHistory = false }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visits) { visit in
                        historyLinkRow(visit) {
                            pendingHistoryLink = visit.link
                            showingLinkHistory = false
                        }
                    }
                }
            }
            if !visits.isEmpty { clearHistoryButton }
        }
        .trickoPage()
        .trickoScreenBackground()
        .foregroundStyle(TrickoStyle.paper)
        .onChange(of: visits.isEmpty) { _, isEmpty in
            if isEmpty { showingLinkHistory = false }
        }
    }

    private func historyLinkRow(_ visit: LessonLinkVisit, open: @escaping () -> Void) -> some View {
        HStack {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: visit.title).font(.stage(.headline)).lineLimit(1)
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
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: ChannelRoute
    @State private var items: [RemoteLessonFile] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var child: ChannelRoute?
    @State private var player: PlayerRoute?
    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                VStack(spacing: 0) {
                    SheetHeading(title: route.title) { dismiss() }
                    ScrollView { channelStatus.trickoPage() }
                }
                .trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
            } else {
                channelList
            }
        }
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 54) }
    }

    private var channelStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            if loading || (!loaded && error == nil) {
                AccountLoadingIndicator(title: "Finding your next lesson…")
                    .frame(maxWidth: .infinity)
            } else if let error {
                EmptyStateCopy(title: "Couldn’t load lessons", message: error)
                Button { Task { await load() } } label: { LocalizedText("Try again") }
                    .buttonStyle(EmptyStateActionStyle(primary: false))
            } else {
                EmptyStateCopy(title: "No lessons yet", message: "This channel has no available videos.")
                if hasMore {
                    Button { Task { await load() } } label: { LocalizedText("Load more") }
                        .buttonStyle(EmptyStateActionStyle(primary: false))
                } else {
                    Button { dismiss() } label: { LocalizedText("Back") }
                        .buttonStyle(EmptyStateActionStyle(primary: false))
                }
            }
        }
    }

    private var channelList: some View {
        VStack(spacing: 0) {
            SheetHeading(title: route.title) { dismiss() }
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(items, id: \.stableID) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 16) {
                                MediaCover(url: WebAddress.media(item.coverImage), folder: item.isFolder == true)
                                    .frame(width: 80, height: 94).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(verbatim: item.name ?? L10n.text("Untitled")).font(.stage(.headline)).lineLimit(3)
                                    LocalizedText(item.isFolder == true ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                                        .font(.caption.monospacedDigit()).foregroundStyle(TrickoStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Glyph(symbol: item.isFolder == true ? .folder : .play, size: 20, tint: TrickoStyle.accent)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    if let error { ErrorNote(message: error) }
                    if hasMore {
                        ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) {
                            Task { await load() }
                        }
                    }
                }.trickoPage()
            }
        }.trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
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
        if item.isFolder == true, let link = item.landingPage?.nilIfBlank {
            child = ChannelRoute(link: link, title: item.name ?? "Folder")
        } else if let clip = item.clip(channel: route.title) {
            player = PlayerRoute(clips: items.compactMap { $0.clip(channel: route.title) }, startID: clip.id, continuesRecommendations: true)
        } else { error = "This item does not contain a playable video." }
    }
}

struct LinkGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Open your next lesson") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    FeatureRow(symbol: .link, title: "1. Copy the link or code", detail: "Use the lesson link or code you received.")
                    FeatureRow(symbol: .search, title: "2. Paste or type", detail: "On Home, tap Paste or enter the code as received. Codes are case-sensitive.")
                    FeatureRow(symbol: .play, title: "3. Open and watch", detail: "Tap Open lesson to find matching lessons, then swipe to watch.")
                    LocalizedText("No results? Check your input, or ask the sender for a new link.")
                        .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.trickoPage()
            }
        }.trickoScreenBackground().foregroundStyle(.white)
    }
}
