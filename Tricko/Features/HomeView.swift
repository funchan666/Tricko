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
    @State private var showingRecentLinks = false
    @State private var showingCollections = true
    @State private var loadingCollections = true
    @State private var composerError: String?
    @State private var reviewingVideo: PracticeRecording?
    @FocusState private var focused: Bool

    var body: some View {
        homePage
            .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            .sheet(isPresented: $paywall) { MembershipView() }
            .sheet(item: $reviewingVideo) { VideoReviewView(movie: $0) }
    }

    private var homePage: some View {
        GeometryReader { viewport in
            let topInset = viewport.safeAreaInsets.top
            let photoHeight = (viewport.size.height + topInset) * 0.5
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        headerActions
                        Spacer(minLength: 0)
                        videoImport
                    }
                    .trickoPage()
                    .frame(minHeight: max(0, photoHeight - topInset), alignment: .top)

                    VStack(alignment: .leading, spacing: 24) {
                        continueReview
                        recentVideos
                        lessonAccess
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
                    .init(color: .clear, location: 0.54),
                    .init(color: TrickoStyle.background.opacity(0.64), location: 0.82),
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

    private var videoImport: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Import a video")
                .font(.stage(.largeTitle, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
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
            Button { openReview(recent.movie) } label: {
                HStack(spacing: 12) {
                    Glyph(symbol: .bookmark, size: 18, tint: TrickoStyle.ink)
                        .frame(width: 36, height: 36)
                        .background(TrickoStyle.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedText("Continue review").font(.stage(.headline, weight: .semibold))
                        Text(verbatim: recent.movie.title)
                            .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .back, size: 11, tint: TrickoStyle.accent).rotationEffect(.degrees(180))
                }
                .padding(14)
                .frame(minHeight: 60)
                .trickoGlass(in: shape)
                .contentShape(.interaction, shape)
            }
            .buttonStyle(PressStyle())
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
                        ForEach(videos) { movie in recentVideo(movie) }
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                Glyph(symbol: .feed, size: 18, tint: TrickoStyle.coolAccent)
                    .frame(width: 36, height: 36)
                    .background(TrickoStyle.raised, in: .rect(cornerRadius: 10))
                LocalizedText("No imported videos yet")
                    .font(.stage(.subheadline, weight: .medium))
                    .foregroundStyle(TrickoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { StageSurface(tone: .smoke, radius: 16) }
        }
    }

    private func recentVideo(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openVideo(movie) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    LocalVideoCover(url: library.url(for: movie), cornerRadius: 12, maximumPixelSize: 640)
                        .aspectRatio(1.52, contentMode: .fit)
                    Text(verbatim: movie.title).font(.stage(.subheadline, weight: .semibold)).lineLimit(2)
                    LocalizedDateText(date: movie.date).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint(LocalizedStringKey("Full editor"))

            VideoReviewButton(movie: movie) { openReview(movie) }
        }
        .frame(width: typeSize.isAccessibilitySize ? 250 : 168, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            linkComposer
            watchLessonsButton
        }
    }

    private var watchLessonsButton: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard searchRequest == nil else { return }
            focused = false
            searchRequest = LessonSearch(query: "")
        } label: {
            HStack(spacing: 12) {
                Glyph(symbol: .play, size: 16, tint: TrickoStyle.ink)
                    .frame(width: 36, height: 36)
                    .background(TrickoStyle.coolAccent, in: Circle())
                LocalizedText("Watch lessons").font(.stage(.headline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 11, tint: TrickoStyle.coolAccent)
                    .rotationEffect(.degrees(180))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 60)
            .foregroundStyle(TrickoStyle.paper)
            .trickoGlass(in: shape)
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .disabled(searchRequest != nil)
        .accessibilityIdentifier("home.watchLessons")
    }

    @ViewBuilder private var lessonResources: some View {
        let visits = library.history.filter { $0.link.nilIfBlank != nil }
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
            linkField
            if let composerError { ErrorNote(message: composerError) }
            LocalizedText("If no videos match, your input is sent to Google Search.")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pasteButton(inline: true)
                    openLessonButton(inline: true)
                }
                VStack(spacing: 8) {
                    pasteButton(inline: false)
                    openLessonButton(inline: false)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    allowanceLabel
                    Spacer(minLength: 0)
                    linkHelpButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    allowanceLabel
                    linkHelpButton
                }
            }
        }.padding(.horizontal, 12).padding(.top, 12)
            .background { StageSurface(tone: .smoke, radius: 20) }
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

    private func openLessonButton(inline: Bool) -> some View {
        Button(action: resolve) {
            let foreground = canOpenLink ? TrickoStyle.ink : TrickoStyle.secondary
            HStack(spacing: 8) {
                Glyph(symbol: .search, size: 14, tint: foreground)
                LocalizedText("Open lesson").font(.stage(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: inline, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(foreground)
            .background(canOpenLink ? TrickoStyle.coolAccent : TrickoStyle.raised, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }.buttonStyle(PressStyle(disabledOpacity: 1)).disabled(!canOpenLink)
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
    private func pasteButton(inline: Bool) -> some View {
        Button(action: pasteCopiedLink) {
            LocalizedText("Paste").font(.stage(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: inline, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minWidth: 44, maxWidth: inline ? nil : .infinity, minHeight: 44)
                .foregroundStyle(TrickoStyle.paper)
                .background { StageSurface(tone: .velvet, radius: 12) }
                .contentShape(.rect(cornerRadius: 12))
        }.buttonStyle(PressStyle())
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visits.prefix(5)) { visit in
                HStack {
                    Button {
                        link = visit.link
                        resolve()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: visit.title).font(.stage(.headline)).lineLimit(1)
                            Text(verbatim: visit.link).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle()).disabled(searchRequest != nil)
                    IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                }
            }
            Button {
                library.clearHistory()
                showingRecentLinks = false
            } label: { LocalizedText("Clear history") }
                .buttonStyle(QuietActionStyle())
        }
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
