import SwiftUI

struct BrowserLessonSearch: Identifiable, Equatable {
    let id = UUID()
    let query: String
    var url: URL? {
        var address = URLComponents(string: "https://www.google.com/search")
        address?.queryItems = [URLQueryItem(name: "q", value: query)]
        if let encoded = address?.percentEncodedQuery {
            address?.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
        return address?.url
    }
}

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var entries: [PlaybackQueueEntry]
    @Published private(set) var loading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    @Published private(set) var emptySearch: BrowserLessonSearch?
    var clips: [LessonClip] { entries.map(\.clip) }
    private var feedID: String?
    private var cursor: String?
    private var roundVideoIDs = Set<String>()
    private var requestQuery = ""
    private(set) var query = ""
    private var generation = UUID()

    init(seed: [LessonClip] = []) {
        entries = seed.map { PlaybackQueueEntry(id: $0.id, clip: $0) }
        hasMore = seed.isEmpty
    }

    func invalidatePendingLoad() {
        generation = UUID()
        loading = false
    }

    func isNearEnd(_ id: String?) -> Bool {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        return index >= entries.count - 3
    }

    func load(api: APIClient, search: String? = nil) async {
        if let search {
            generation = UUID()
            entries = []; feedID = nil; cursor = nil; hasMore = true; loading = false
            query = search; requestQuery = search; roundVideoIDs = []
            emptySearch = nil
        }
        guard !loading else { return }
        let current = generation
        loading = true
        error = nil
        defer {
            if generation == current {
                if !Task.isCancelled { hasLoaded = true }
                loading = false
            }
        }
        do {
            for _ in 0..<3 {
                if !hasMore {
                    if entries.isEmpty, requestQuery.nilIfBlank != nil { break }
                    feedID = nil; cursor = nil; roundVideoIDs = []
                    requestQuery = ""
                    hasMore = true
                }
                let previousCursor = cursor
                let response = try await api.feed(query: requestQuery, feedID: feedID, cursor: cursor)
                try Task.checkCancellation()
                guard current == generation else { return }
                let additions = response.list.compactMap(\.clip).filter { roundVideoIDs.insert($0.id).inserted }
                    .map { PlaybackQueueEntry(id: UUID().uuidString, clip: $0) }
                feedID = response.feedId?.nilIfBlank
                cursor = response.nextCursor?.nilIfBlank
                hasMore = response.hasMore && cursor != nil && cursor != previousCursor
                if !additions.isEmpty { entries += additions; return }
                if response.list.isEmpty {
                    hasMore = false
                    if entries.isEmpty, requestQuery.nilIfBlank != nil {
                        emptySearch = BrowserLessonSearch(query: requestQuery)
                    }
                    break
                }
            }
            if entries.isEmpty, requestQuery.nilIfBlank != nil {
                emptySearch = BrowserLessonSearch(query: requestQuery)
            }
            if !entries.isEmpty { error = "No more videos are available right now. Try again." }
        } catch is CancellationError {
        } catch {
            if current == generation, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    private let onExit: () -> Void
    private let onSearchResult: ((String, LessonClip) -> Void)?
    @EnvironmentObject private var offline: OfflineStore
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    private let morePageID = "recommendation-tail"
    @EnvironmentObject private var api: APIClient
    @StateObject private var feed = FeedStore()
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var visible = false
    @State private var activeID: String?
    @State private var recordedQuery: String?
    @State private var openedBrowserSearchID: UUID?
    @State private var browserSearch: PolicyDocument?
    @State private var retry = 0
    @State private var loadedFeedRequest: FeedRequest?
    private var feedRequest: FeedRequest { FeedRequest(ownerID: api.session?.userId.value, retry: retry) }
    init(initialSearch: String, onExit: @escaping () -> Void,
         onSearchResult: ((String, LessonClip) -> Void)? = nil) {
        self.onExit = onExit
        self.onSearchResult = onSearchResult
        _search = State(initialValue: initialSearch)
    }
    var body: some View {
        ZStack(alignment: .top) {
            if api.session == nil || feed.clips.isEmpty {
                VStack(spacing: 0) {
                    feedHeader
                    ScrollView {
                        feedStatus.trickoPage()
                    }
                }
                .trickoScreenBackground()
            } else {
                GeometryReader { container in
                    let controlInsets = container.safeAreaInsets
                    GeometryReader { geometry in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(displayEntries) { entry in
                                    let clip = entry.clip
                                    Group {
                                        if let playback = players.controllers[entry.id] {
                                            ClipPage(clip: clip, active: activeID == entry.id,
                                                     controlInsets: controlInsets, playback: playback,
                                                     didStartPlaying: { players.prepareNext(after: entry.id) },
                                                     didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                                     onSwipeExit: exitPlayer)
                                        } else {
                                            PlayerPoster(url: clip.coverURL)
                                        }
                                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped().id(entry.id)
                                }
                                if !feed.entries.isEmpty {
                                    MoreLessonsStatus(loading: feed.loading, error: feed.error) {
                                        Task { await feed.load(api: api) }
                                    }.padding(28).padding(controlInsets)
                                        .frame(width: geometry.size.width, height: geometry.size.height).id(morePageID)
                                }
                            }.scrollTargetLayout()
                        }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top).scrollIndicators(.hidden)
                            .onChange(of: activeID) { _, id in
                                players.update(entries: displayEntries, selectedID: id)
                            }
                    }.ignoresSafeArea(.container, edges: .all)
                }
                feedHeader
            }
        }.trickoScreenBackground(feed.clips.isEmpty ? TrickoStyle.background : .black)
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 56) }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { players.releaseAll() }
            }
            .onAppear { visible = true; players.update(entries: displayEntries, selectedID: activeID) }
            .task(id: feedRequest) {
                let request = feedRequest
                guard !Task.isCancelled else { return }
                guard request.ownerID != nil else {
                    loadedFeedRequest = nil
                    return
                }
                guard request != loadedFeedRequest else { return }
                await feed.load(api: api, search: search)
                guard !Task.isCancelled, request == feedRequest else { return }
                loadedFeedRequest = request
                activeID = feed.entries.first?.id
            }
            .onChange(of: activeID) { _, id in
                guard visible, api.session != nil,
                      id == morePageID || feed.isNearEnd(id) else { return }
                Task { guard visible else { return }; await feed.load(api: api) }
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count {
                    activeID = entries[previous.count].id
                } else if !entries.contains(where: { $0.id == activeID }) { activeID = entries.first?.id }
                players.update(entries: displayEntries, selectedID: activeID)
                if let first = entries.first?.clip, recordedQuery != feed.query {
                    recordedQuery = feed.query
                    onSearchResult?(feed.query, first)
                }
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.pauseAll() }
            .fullScreenCover(item: $browserSearch) { document in
                PolicyBrowser(document: document, webSearch: true)
            }
            .onChange(of: feed.emptySearch) { _, _ in openPendingBrowserSearch() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { players.suspend() }
                else { openPendingBrowserSearch() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private var feedStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            if api.session == nil {
                ConnectionPanel()
            } else if feed.loading || !feed.hasLoaded {
                StageLoadingIndicator(title: "Loading videos…")
                    .frame(maxWidth: .infinity)
            } else if let error = feed.error {
                EmptyStatePanel(symbol: .feed) {
                    EmptyStateCopy(title: "Couldn’t load videos", message: error)
                    retryButton
                }
            } else if let request = feed.emptySearch {
                EmptyStatePanel(symbol: .search) {
                    EmptyStateCopy(title: "No videos found", message: "Search the web with your original input.")
                    Button { openBrowserSearch(request) } label: { LocalizedText("Search in browser") }
                        .buttonStyle(EmptyStateActionStyle())
                }
            } else {
                EmptyStatePanel(symbol: .feed) {
                    EmptyStateCopy(title: "No videos to show", message: "To play your own video, choose Files or Photos on Home.")
                    retryButton
                }
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retryButton: some View {
        Button(action: retryLessons) { LocalizedText("Try again") }
            .buttonStyle(EmptyStateActionStyle(primary: false))
    }

    private func retryLessons() {
        retry += 1
    }

    private func openPendingBrowserSearch() {
        guard visible, scenePhase == .active, let request = feed.emptySearch,
              openedBrowserSearchID != request.id else { return }
        openBrowserSearch(request)
    }
    private func openBrowserSearch(_ request: BrowserLessonSearch) {
        guard let url = request.url else { return }
        openedBrowserSearchID = request.id
        players.suspend()
        browserSearch = PolicyDocument(title: "Web search", url: url)
    }
    private var feedHeader: some View {
        HStack {
            Spacer(minLength: 0)
            PlayerExitButton(action: exitPlayer)
        }.environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 12).padding(.top, 8)
    }
    private func exitPlayer() {
        players.releaseAll()
        onExit()
    }

}

private struct FeedRequest: Equatable {
    let ownerID: String?
    let retry: Int
}

private struct MoreLessonsStatus: View {
    let loading: Bool
    let error: String?
    let load: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let error {
                MessagePanel(title: "Couldn’t load videos", message: error, actionTitle: "Try again", action: load)
            } else if loading {
                StageLoadingIndicator(title: "Finding more clips…")
            } else {
                Button(action: load) { LocalizedText("Load more") }
                    .buttonStyle(EmptyStateActionStyle(primary: false))
            }
        }.frame(maxWidth: 460)
    }
}

struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: PlayerRoute
    @State private var visible = false
    @State private var activeID: String?
    @StateObject private var feed: FeedStore
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    private let morePageID = "collection-recommendation-tail"
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    init(route: PlayerRoute) {
        self.route = route
        _activeID = State(initialValue: route.startID)
        _feed = StateObject(wrappedValue: FeedStore(seed: route.clips))
    }
    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayEntries) { entry in
                            let clip = entry.clip
                            Group {
                                if let playback = players.controllers[entry.id] {
                                    ClipPage(clip: clip, active: activeID == entry.id,
                                             supportsPaging: displayEntries.count > 1 || route.continuesRecommendations,
                                             controlInsets: container.safeAreaInsets, playback: playback,
                                             didStartPlaying: { players.prepareNext(after: entry.id) },
                                             didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                             onSwipeExit: exitPlayer)
                                } else { PlayerPoster(url: clip.coverURL) }
                            }.containerRelativeFrame([.horizontal, .vertical]).clipped().id(entry.id)
                        }
                        if route.continuesRecommendations {
                            MoreLessonsStatus(loading: feed.loading, error: feed.error) {
                                Task { await feed.load(api: api) }
                            }.padding(28).padding(container.safeAreaInsets)
                                .containerRelativeFrame([.horizontal, .vertical]).id(morePageID)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top)
                .scrollIndicators(.hidden)
                .task {
                    if let activeID { proxy.scrollTo(activeID, anchor: .top) }
                }
            }.ignoresSafeArea(.container, edges: .all)
        }.trickoScreenBackground(.black).overlay(alignment: .top) {
            HStack {
                Spacer(minLength: 0)
                PlayerExitButton(action: exitPlayer)
            }.environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 12).padding(.top, 8)
        }.preferredColorScheme(.dark)
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 56) }
            .onChange(of: library.downloadsRequest) { _, request in if request != nil { exitPlayer() } }
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .onAppear {
                visible = true
                players.update(entries: displayEntries, selectedID: activeID)
                continueFeedIfNeeded(activeID)
            }
            .onChange(of: activeID) { _, id in
                players.update(entries: displayEntries, selectedID: id)
                continueFeedIfNeeded(id)
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count { activeID = entries[previous.count].id }
                players.update(entries: displayEntries, selectedID: activeID)
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.pauseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private func exitPlayer() {
        players.releaseAll()
        dismiss()
    }
    private func continueFeedIfNeeded(_ id: String?) {
        guard visible, route.continuesRecommendations, id == morePageID || feed.isNearEnd(id) else { return }
        Task { guard visible else { return }; await feed.load(api: api) }
    }
}

private struct PlaybackGateKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var playbackGatePresented: Bool {
        get { self[PlaybackGateKey.self] }
        set { self[PlaybackGateKey.self] = newValue }
    }
}

private struct PlayerPagingAccess: ViewModifier {
    let entries: [PlaybackQueueEntry]
    @Binding var selectedID: String?
    let tailID: String
    @ObservedObject var players: PlaybackPool
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var admittedID: String?
    @State private var requestedID: String?
    @State private var showingWatchOptions = false
    @State private var swipeOrigin: String?
    @State private var trackingSwipe = false
    @State private var swipeEnded: UUID?
    @AppStorage("tricko.player.completedSwipeHint.v6") private var completedHint = false

    func body(content: Content) -> some View {
        content
            .environment(\.playbackGatePresented, showingWatchOptions)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
                guard !showingWatchOptions, abs(value.translation.height) > abs(value.translation.width) else { return }
                if !trackingSwipe { trackingSwipe = true; swipeOrigin = admittedID; swipeEnded = nil }
            }.onEnded { _ in swipeEnded = UUID() })
            .task(id: swipeEnded) {
                guard swipeEnded != nil else { return }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                trackingSwipe = false; swipeOrigin = nil
            }
            .onAppear { admit(selectedID) }
            .onChange(of: selectedID) { _, value in admit(value) }
            .fullScreenCover(isPresented: $showingWatchOptions, onDismiss: finishWatchOptions) {
                AllowanceLimitPrompt(kind: .watch)
            }
    }
    private func canWatch(_ id: String) -> Bool {
        guard let clip = entries.first(where: { $0.id == id })?.clip else { return false }
        return clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
    }
    private func admit(_ id: String?) {
        guard !showingWatchOptions, let id else { return }
        if let admittedID, !entries.contains(where: { $0.id == admittedID }) { self.admittedID = nil }
        let isTail = id == tailID
        if canWatch(id) || (isTail && !quota.canRequestReward(for: .watch, premium: commerce.premium)) {
            if !isTail {
                if trackingSwipe, let swipeOrigin, swipeOrigin != id, admittedID != id {
                    completedHint = true
                }
                admittedID = id
            }
            return
        }
        guard isTail || entries.contains(where: { $0.id == id }) else { return }
        requestedID = id
        players.pauseAll()
        if let admittedID, admittedID != id {
            showingWatchOptions = true
            selectedID = admittedID
        } else {
            admittedID = id
            if quota.claimWatchLimitPrompt(premium: commerce.premium) { showingWatchOptions = true }
        }
    }
    private func finishWatchOptions() {
        if let requestedID {
            let canContinueFeed = requestedID == tailID && !quota.canRequestReward(for: .watch, premium: commerce.premium)
            if canContinueFeed || canWatch(requestedID) { selectedID = requestedID }
        }
        requestedID = nil
    }
}

struct AllowanceLimitPrompt: View {
    let kind: AllowanceKind
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var showingPlus = false
    @State private var rewardTask: Task<Void, Never>?
    @State private var previousRewardID: UUID?
    @State private var previousLuckyRewardID: UUID?

    private var canWatchAd: Bool { quota.canRequestReward(for: kind, premium: commerce.premium) }
    private var heading: String {
        switch kind {
        case .watch: canWatchAd ? "Out of views" : "Playback unavailable"
        case .download: canWatchAd ? "Get more downloads" : "Download options"
        }
    }
    private var adBusy: Bool { ads.busy || ads.isPresenting || ads.isPreparingAppOpen }
    private var adFeedback: String? {
        guard rewardTask != nil, !adBusy else { return nil }
        return ads.error ?? ads.message ?? "Rewarded ads are not available right now. No views have been deducted."
    }

    var body: some View {
        ZStack {
            if rewardTask != nil, let reward = ads.luckyReward, reward.id != previousLuckyRewardID {
                LuckyRewardView(message: reward.message) {
                    ads.luckyReward = nil
                    dismiss()
                }
            } else {
                GeometryReader { viewport in
                    ScrollView {
                        choices
                            .padding(20)
                            .frame(maxWidth: 352, alignment: .leading)
                            .background { StageSurface(tone: .smoke, radius: 24) }
                            .padding(24)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                    }
                }
                .background { Color.black.opacity(0.66).ignoresSafeArea() }
                .foregroundStyle(TrickoStyle.paper)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, cancel)
                .onAppear { headingFocused = true }
            }
        }
        .trickoImmersiveChrome()
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showingPlus, onDismiss: {
            if commerce.premium { dismiss() }
        }) {
            MembershipView()
        }
        .onAppear(perform: finishAdIfRewarded)
        .onChange(of: ads.completedReward) { _, _ in finishAdIfRewarded() }
        .onChange(of: commerce.premium) { _, active in
            if active, !showingPlus, !ads.isPresenting { dismiss() }
        }
        .onDisappear { cancelRewardLoading() }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(heading)
                    .font(.stage(.title2, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                if let message = adFeedback ?? quota.error ?? (canWatchAd ? quota.rewardSummary(for: kind) : nil) {
                    LocalizedText(message)
                        .font(.stage(.subheadline))
                        .foregroundStyle(TrickoStyle.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                if canWatchAd {
                    Button(action: watchAd) {
                        HStack(spacing: 8) {
                            if ads.busy { StageActivityMark(size: 16) }
                            LocalizedText(ads.busy ? "Loading ad…" : "Watch an ad")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EmptyStateActionStyle())
                    .disabled(adBusy)
                }
                Button {
                    showingPlus = true
                } label: {
                    LocalizedText("Get Plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(EmptyStateActionStyle(primary: !canWatchAd))
                .disabled(ads.busy || ads.isPresenting)
                Button(action: cancel) {
                    LocalizedText("Cancel")
                        .font(.stage(.footnote, weight: .semibold))
                        .foregroundStyle(TrickoStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(ads.isPresenting)
            }
            .multilineTextAlignment(.center)
        }
    }

    private func watchAd() {
        guard canWatchAd, !adBusy else { return }
        rewardTask?.cancel()
        previousRewardID = ads.completedReward
        previousLuckyRewardID = ads.luckyReward?.id
        rewardTask = Task { await ads.watch(commerce: commerce, quota: quota, kind: kind) }
    }

    private func finishAdIfRewarded() {
        guard rewardTask != nil, let completion = ads.completedReward, completion != previousRewardID else { return }
        previousRewardID = completion
        dismiss()
    }

    private func cancel() {
        guard !ads.isPresenting else { return }
        cancelRewardLoading()
        dismiss()
    }

    private func cancelRewardLoading() {
        guard let rewardTask, !ads.isPresenting, !ads.isPresentingConsent else { return }
        rewardTask.cancel()
        self.rewardTask = nil
        ads.cancelRewardLoading()
    }
}

private struct PlayerSwipeHint: View {
    let eligible: Bool
    @AppStorage("tricko.player.completedSwipeHint.v6") private var alreadyShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var showing = false
    var body: some View {
        GeometryReader { container in
            let width = max(0, container.size.width)
            let height = max(0, container.size.height)
            let artworkHeight = min(width * 1.18, height * 0.64, 520)
            ZStack {
                Color.clear
                if showing && eligible && !alreadyShown && phase == .active {
                    VStack(spacing: min(24, height * 0.04)) {
                        Color.clear.frame(width: width, height: artworkHeight)
                            .phaseAnimator([0, 1, 2, 3, 4]) { host, step in
                                host.overlay {
                                    let resting = step == 0 || step == 4
                                    ZStack {
                                        Image("TrickoSwipeTrail").resizable().scaledToFit()
                                            .frame(width: artworkHeight * 0.56, height: artworkHeight)
                                            .offset(x: -artworkHeight * 0.12)
                                            .opacity(reduceMotion ? 0.7 : (resting ? 0.25 : 0.9))
                                            .scaleEffect(reduceMotion || resting ? 0.94 : 1)
                                        Image("TrickoSwipeGesture").resizable().scaledToFit()
                                            .frame(width: artworkHeight * 0.48, height: artworkHeight * 0.48)
                                            .shadow(color: TrickoStyle.accent.opacity(0.25), radius: 6)
                                            .rotationEffect(.degrees(reduceMotion ? 0 : (step == 2 ? -5 : 3)))
                                            .offset(x: artworkHeight * 0.1,
                                                    y: reduceMotion ? 0 : (step == 2 ? -1 : 1) * artworkHeight * 0.22)
                                            .opacity(reduceMotion ? 1 : (resting ? 0.15 : 1))
                                    }
                                }
                            } animation: { step in
                                reduceMotion ? nil : .easeInOut(duration: step == 2 || step == 3 ? 0.85 : 0.3)
                            }
                        LocalizedText("Swipe up or down to change videos")
                            .font(.stage(.title3, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }
            }.frame(width: width, height: height)
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showing)
        .task(id: eligible && phase == .active) {
            showing = false
            guard eligible, phase == .active, !alreadyShown else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                showing = true
                try await Task.sleep(for: .seconds(6))
                try Task.checkCancellation()
                alreadyShown = true
            } catch { }
            showing = false
        }
    }
}

struct ClipPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.scenePhase) private var phase
    @Environment(\.playbackGatePresented) private var pagingGate
    let clip: LessonClip
    let active: Bool
    var supportsPaging = true
    var controlInsets = EdgeInsets()
    @ObservedObject var playback: PlaybackController
    var didStartPlaying: () -> Void = {}
    var didStopPlaying: () -> Void = {}
    var onSwipeExit: () -> Void = {}
    @State private var visible = false
    @State private var firstFrameReady = false
    @State private var accessChecked = false
    @State private var resumeAfterSheet = false
    @State private var resumeAfterInterruption = false
    @State private var gate = false
    @State private var options = false
    @State private var editor = false
    @State private var downloadPanel = false
    @State private var downloadStarting = false
    @State private var downloadReward = false
    @State private var recorded = false
    @State private var allowed = false
    @State private var scrubbing = false
    @State private var favoriteError: String?
    @ScaledMetric(relativeTo: .subheadline) private var speedOptionWidth: CGFloat = 56
    var body: some View {
        ZStack {
            Color.black
            GeometryReader { page in
                VideoSurface(player: playback.player, fill: page.size.height >= page.size.width * 1.4,
                             onReadyForDisplay: { firstFrameReady = $0 })
            }
                .clipped().allowsHitTesting(false)
            if !firstFrameReady {
                PlayerPoster(url: clip.coverURL)
                    .allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                guard active, phase == .active, !ads.isPresenting else { return }
                if allowed, firstFrameReady { playback.toggle() }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
                guard active, visible, phase == .active, !ads.isPresenting,
                      !pagingGate, !gate, !options, !editor, !downloadPanel,
                      !downloadReward, !scrubbing,
                      value.translation.width < -90,
                      abs(value.translation.width) > abs(value.translation.height) * 1.7 else { return }
                onSwipeExit()
            })
            LinearGradient(stops: [.init(color: .black.opacity(0.38), location: 0),
                                   .init(color: .clear, location: 0.2),
                                   .init(color: .clear, location: 0.53),
                                   .init(color: .black.opacity(0.68), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false).accessibilityHidden(true)
            playerControls
            if active, let favoriteError {
                VStack {
                    HStack(spacing: 10) {
                        LocalizedText(favoriteError).font(.stage(.caption))
                        IconButton(symbol: .close, label: "Dismiss message") { self.favoriteError = nil }
                    }.padding(12).background { StageSurface(tone: .velvet) }
                    Spacer()
                }.padding(.top, controlInsets.top + 60).padding(.horizontal, 16)
            }
            PlayerSwipeHint(eligible: supportsPaging && active && visible && playback.error == nil &&
                            !pagingGate && !gate && !options && !editor && !downloadPanel && !downloadReward && !ads.isPresenting)
                .padding(.top, controlInsets.top + 64)
                .padding(.bottom, controlInsets.bottom + 150)
                .padding(.leading, controlInsets.leading + 20)
                .padding(.trailing, controlInsets.trailing + 72)
            if active, visible, !pagingGate, !gate, !options, !editor, !downloadPanel, !downloadReward {
                if accessChecked, !allowed {
                    EmptyStatePanel(symbol: .play) {
                        LocalizedText(quota.canRequestReward(for: .watch, premium: commerce.premium)
                                      ? "Out of views" : "Playback unavailable")
                            .font(.stage(.title3, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        ActionButton(title: "View options") { gate = true }
                    }.frame(maxWidth: 320).padding(24)
                } else if let error = playback.error {
                    MessagePanel(title: "This clip couldn’t load", message: error, actionTitle: "Retry") { activate(reload: true) }.padding(24)
                } else if allowed, playback.isLoading || (!firstFrameReady && playback.intendsPlayback) {
                    PlayerLoadingFeedback(buffering: firstFrameReady)
                        .allowsHitTesting(false)
                } else if allowed, firstFrameReady, !playback.intendsPlayback, !scrubbing {
                    IconButton(symbol: .play, label: "Play video") { playback.play() }
                        .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                }
            }
        }.foregroundStyle(.white).clipped()
            .onAppear { visible = true; if active { activate() } }
            .onChange(of: active) { _, active in
                resumeAfterInterruption = false
                if active { activate() } else { favoriteError = nil; resumeAfterSheet = false; playback.pause() }
            }
            .onChange(of: playback.isPlaying) { _, playing in
                if playing, active, visible, !recorded {
                    recorded = clip.playbackURL.isFileURL || quota.recordWatch(clip.id, premium: commerce.premium)
                    if !recorded { playback.pause(); allowed = false }
                }
                if playing, active, recorded { didStartPlaying() }
                if !playing, active { didStopPlaying() }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard active, visible, playback.isPlaying, !clip.playbackURL.isFileURL else { return }
                if !quota.recordWatch(clip.id, premium: commerce.premium) { playback.pause(); allowed = false }
            }
            .onChange(of: phase) { _, state in
                if state != .active { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onChange(of: ads.isPresenting) { _, presenting in
                if presenting { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onDisappear { visible = false; resumeAfterInterruption = false; playback.pause() }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { options = false; downloadPanel = false; editor = false }
            }
            .onChange(of: gate) { _, presented in if presented { playback.pause() } }
            .onChange(of: pagingGate) { _, presented in
                if presented { playback.pause() } else if active { activate() }
            }
            .fullScreenCover(isPresented: $gate, onDismiss: { if active { activate() } }) { AllowanceLimitPrompt(kind: .watch) }
            .onChange(of: options) { _, open in if !open { resumeAfterControls() } }
            .onChange(of: downloadPanel) { _, open in if !open { resumeAfterControls() } }
            .fullScreenCover(isPresented: $downloadReward, onDismiss: resumeAfterControls) { AllowanceLimitPrompt(kind: .download) }
    }

    private var playbackOptions: some View {
        PlayerControlPopover(title: "Playback", close: { options = false }) {
            LocalizedText("Speed").font(.stage(.headline))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: speedOptionWidth), spacing: 6)], spacing: 6) {
                ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { speed in
                    Button { playback.setSpeed(speed) } label: {
                        Text("\(speed, specifier: "%g")×")
                            .font(.stage(.subheadline, weight: .semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(playback.speed == speed ? TrickoStyle.ink : TrickoStyle.paper)
                            .background { StageSurface(tone: playback.speed == speed ? .gold : .velvet, radius: 12) }
                            .contentShape(Rectangle())
                    }.accessibilityAddTraits(playback.speed == speed ? .isSelected : [])
                }
            }.buttonStyle(PressStyle())
            LocalizedText("Supported streams adjust quality to your connection.")
                .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
            VideoExportEntry(clip: clip)
            ActionButton(title: "Edit a local video", primary: false) { editor = true }
            DisclosureGroup("Downloads") {
                OfflineDownloadButton(clip: clip, showsExport: false).padding(.top, 8)
            }
        }
        .fullScreenCover(isPresented: $editor, onDismiss: resumeAfterControls) { EditorSheet() }
    }

    private var playerControls: some View {
        GeometryReader { viewport in
            let insets = resolvedControlInsets(in: viewport)
            let height = viewport.size.height - insets.top - insets.bottom
            playerControlContent(compact: height < 270)
                .padding(insets)
        }
    }
    private func playerControlContent(compact: Bool) -> some View {
        let row = compact
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 16))
        let rail = compact
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))
        return VStack(spacing: 0) {
            Spacer(minLength: 16)
            row {
                VStack(alignment: .leading, spacing: 7) {
                    if !clip.channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: clip.channel).font(.stage(.subheadline, weight: .bold)).lineLimit(2)
                    }
                    Text(verbatim: clip.title).font(.stage(.subheadline)).lineLimit(2)
                        .accessibilityLabel(clip.title)
                }
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                rail {
                    PlayerRailButton(artwork: library.isSaved(clip) ? .saved : .save,
                                     title: library.isSaved(clip) ? "Favorited" : "Favorite",
                                     accessibilityTitle: library.isSaved(clip) ? "Remove saved video" : "Save video",
                                     selected: library.isSaved(clip), action: save)
                    PlayerCacheButton(clip: clip, action: cacheVideo)
                        .popover(isPresented: $downloadPanel) {
                            PlayerControlPopover(title: "Downloads", close: { downloadPanel = false }) {
                                Text(verbatim: clip.title).font(.stage(.headline))
                                    .fixedSize(horizontal: false, vertical: true)
                                OfflineDownloadButton(clip: clip, starting: downloadStarting)
                            }
                        }
                    PlayerRailButton(artwork: .more, title: "More", accessibilityTitle: "Playback options") {
                        resumeAfterSheet = playback.intendsPlayback
                        playback.pause(); options = true
                    }.popover(isPresented: $options) { playbackOptions }
                }.padding(.bottom, 8)
            }.padding(.leading, 4)
            PlayerProgressControl(playback: playback, timeline: playback.timeline,
                                  enabled: allowed && firstFrameReady,
                                  canResume: active && allowed && phase == .active && !ads.isPresenting,
                                  scrubbing: $scrubbing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }
    private func resolvedControlInsets(in viewport: GeometryProxy) -> EdgeInsets {
        guard #available(iOS 27.1, *) else { return controlInsets }
        let size = viewport.size
        var insets = controlInsets
        func usableBounds() -> CGRect {
            CGRect(x: insets.leading, y: insets.top,
                   width: max(0, size.width - insets.leading - insets.trailing),
                   height: max(0, size.height - insets.top - insets.bottom))
        }
        for region in viewport.reservedRegions(kind: .division) where region.isActive {
            let bounds = usableBounds()
            let split = region.frame.intersection(bounds)
            guard !split.isNull, !split.isEmpty else { continue }
            if split.height >= split.width {
                let leadingWidth = split.minX - bounds.minX
                let trailingWidth = bounds.maxX - split.maxX
                if trailingWidth >= 242 || trailingWidth >= leadingWidth {
                    insets.leading = split.maxX
                } else {
                    insets.trailing = size.width - split.minX
                }
            } else {
                let upperHeight = split.minY - bounds.minY
                let lowerHeight = bounds.maxY - split.maxY
                if lowerHeight >= 150 || lowerHeight >= upperHeight {
                    insets.top = split.maxY
                } else {
                    insets.bottom = size.height - split.minY
                }
            }
        }
        for region in viewport.reservedRegions(kind: .occlusion) where region.isActive {
            let bounds = usableBounds()
            let obstruction = region.frame.intersection(bounds)
            guard !obstruction.isNull, !obstruction.isEmpty,
                  obstruction.maxY > bounds.maxY - 144 else { continue }
            if obstruction.midX < bounds.midX, bounds.maxX - obstruction.maxX >= 242 {
                insets.leading = obstruction.maxX
            } else if obstruction.midX >= bounds.midX, obstruction.minX - bounds.minX >= 242 {
                insets.trailing = size.width - obstruction.minX
            } else {
                insets.bottom = size.height - obstruction.minY
            }
        }
        return insets
    }
    private func activate(reload: Bool = false) {
        guard active, visible, phase == .active, !ads.isPresenting, !pagingGate,
              !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        recorded = false
        accessChecked = true
        allowed = clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
        if !allowed {
            playback.pause()
            return
        }
        if playback.loadedURL != clip.playbackURL || reload {
            firstFrameReady = false
            playback.load(clip.playbackURL, autoplay: true)
        }
        else { playback.play() }
    }
    private func resumeAfterControls() {
        guard resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        resumeAfterSheet = false
        activate()
    }
    private func interruptPlayback() {
        if active, visible, playback.intendsPlayback { resumeAfterInterruption = true }
        playback.pause()
    }
    private func resumeIfNeeded() {
        guard resumeAfterInterruption || resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        resumeAfterInterruption = false
        resumeAfterSheet = false
        activate()
    }
    private func cacheVideo() {
        if downloadStarting || offline.cached(clip.id) != nil || offline.busy || clip.playbackURL.isFileURL {
            showDownloadPanel()
        } else if !quota.mayDownload(clip.id, premium: commerce.premium) {
            resumeAfterSheet = playback.intendsPlayback
            playback.pause(); downloadReward = true
        } else {
            downloadStarting = true
            showDownloadPanel()
            Task { @MainActor in
                defer { downloadStarting = false }
                await offline.download(clip)
            }
        }
    }
    private func showDownloadPanel() {
        guard !downloadPanel else { return }
        resumeAfterSheet = playback.intendsPlayback
        playback.pause(); downloadPanel = true
    }
    private func save() {
        favoriteError = nil
        if !library.toggle(offline.cached(clip.id)?.clip ?? clip) {
            favoriteError = "Favorites could not be updated. Please try again."
            library.error = nil
        }
    }
}

private struct PlayerControlPopover<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StageSheetHeader(title: title, close: close)
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 340, idealHeight: contentHeight)
        .foregroundStyle(TrickoStyle.paper)
        .presentationCompactAdaptation(.popover)
        .accessibilityAction(.escape, close)
    }
}

private struct PlayerExitButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Glyph(symbol: .exit, size: 14, tint: TrickoStyle.paper)
                LocalizedText("Exit").font(.stage(.caption, weight: .semibold))
                    .foregroundStyle(TrickoStyle.paper).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background { StageSurface(tone: .velvet, radius: 8).opacity(0.9) }
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey("Exit"))
            .accessibilityIdentifier("player.exit")
    }
}

private struct PlayerCacheButton: View {
    let clip: LessonClip
    let action: () -> Void
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.locale) private var locale
    private var cached: Bool { offline.cached(clip.id) != nil || clip.playbackURL.isFileURL }
    var body: some View {
        let preparing = !cached && offline.preparingID == clip.id
        let progress = !cached && offline.downloadingID == clip.id ? offline.progress : nil
        let percentage = progress?.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down).locale(locale))
        Button(action: action) {
            PlayerRailLabel(artwork: .download, selected: cached, preparing: preparing, progress: progress) {
                if cached { LocalizedText("Offline") }
                else if preparing { LocalizedText("Loading…") }
                else if let percentage { Text(verbatim: percentage).monospacedDigit() }
                else { LocalizedText("Download") }
            }
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: L10n.text(cached ? "Available offline" : "Download for offline",
                                                         language: AppLanguage.from(locale))))
            .accessibilityValue(Text(verbatim: preparing ? L10n.text("Loading…", language: AppLanguage.from(locale)) : percentage ?? ""))
            .accessibilityIdentifier("player.cacheVideo")
    }
}

struct PlayerProgressControl: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: PlaybackTimeline
    let enabled: Bool
    let canResume: Bool
    @Binding var scrubbing: Bool
    @State private var scrubPosition: Double = 0
    @State private var resumeAfterScrub = false
    var body: some View {
        TrickoScrubber(value: Binding(
                get: { scrubbing ? scrubPosition : timeline.elapsed },
                set: {
                    scrubPosition = $0
                    if !scrubbing { playback.seek($0) }
                }
            ), range: 0...max(1, timeline.duration), label: "Playback position",
                         tint: .white, trackHeight: scrubbing ? 5 : 2,
                         onEditingChanged: { editing in
                if editing {
                    scrubPosition = timeline.elapsed
                    resumeAfterScrub = playback.isPlaying
                    scrubbing = true
                    playback.pause()
                } else {
                    playback.seek(scrubPosition)
                    scrubbing = false
                    if resumeAfterScrub && canResume {
                        playback.play()
                    }
                    resumeAfterScrub = false
                }
            })
            .disabled(!enabled || timeline.duration <= 0 || playback.error != nil)
            .overlay(alignment: .top) {
                if scrubbing {
                    Text(verbatim: "\(durationLabel(scrubPosition)) / \(durationLabel(timeline.duration))")
                        .environment(\.layoutDirection, .leftToRight)
                        .font(.caption.monospacedDigit()).offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PlayerPoster: View {
    let url: URL?
    var body: some View {
        Color.black.overlay {
            GeometryReader { geometry in
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PlayerLoadingFeedback: View {
    let buffering: Bool
    @State private var revealed = false
    var body: some View {
        StageLoadingIndicator(title: buffering ? "Buffering…" : "Loading…", compact: true)
            .opacity(revealed ? 1 : 0).accessibilityHidden(!revealed)
            .task {
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); revealed = true }
                catch { }
            }
            .onDisappear { revealed = false }
    }
}

struct TrickoScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var tint: Color = TrickoStyle.accent
    var trackHeight: CGFloat = 4
    var onEditingChanged: (Bool) -> Void = { _ in }
    @GestureState private var dragging = false
    @State private var editing = false
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard value.isFinite, range.lowerBound.isFinite, span.isFinite, span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: trackHeight)
                Capsule().fill(tint).frame(width: geometry.size.width * fraction, height: trackHeight)
            }.frame(height: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, state, _ in state = true }.onChanged { gesture in
                    if !editing { editing = true; onEditingChanged(true) }
                    value = range.lowerBound + min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                }.onEnded { _ in finishEditing() })
        }.frame(height: 44).environment(\.layoutDirection, .leftToRight)
            .accessibilityElement().accessibilityLabel(LocalizedStringKey(label))
            .onChange(of: dragging) { _, dragging in if !dragging { finishEditing() } }
            .accessibilityValue(durationLabel(value)).accessibilityAdjustableAction { direction in
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
            }
    }
    private func finishEditing() {
        guard editing else { return }
        editing = false
        onEditingChanged(false)
    }
}

private enum PlayerArtwork: CaseIterable, Hashable {
    case save, saved, download, more
    var glyph: TrickoGlyph {
        switch self {
        case .save: .bookmark
        case .saved: .saved
        case .download: .download
        case .more: .more
        }
    }
}

private struct PlayerRailLabel<Label: View>: View {
    let artwork: PlayerArtwork
    let selected: Bool
    let preparing: Bool
    let progress: Double?
    private let label: Label
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 16
    init(artwork: PlayerArtwork, selected: Bool, preparing: Bool = false, progress: Double? = nil,
         @ViewBuilder label: () -> Label) {
        self.artwork = artwork
        self.selected = selected
        self.preparing = preparing
        self.progress = progress
        self.label = label()
    }
    var body: some View {
        VStack(spacing: 4) {
            if preparing {
                StageActivityMark(size: 17)
                    .frame(width: 30, height: 30)
                    .trickoGlass(in: Circle(), interactive: false)
            } else if let progress {
                VStack(spacing: 2) {
                    Glyph(symbol: artwork.glyph, size: 16, tint: TrickoStyle.paper)
                    StageProgressTrack(value: progress).frame(width: 20)
                }
                .frame(width: 30, height: 30)
                .trickoGlass(in: .rect(cornerRadius: 8), interactive: false)
            } else {
                Glyph(symbol: artwork.glyph, size: 22, tint: selected ? TrickoStyle.accent : TrickoStyle.paper)
                    .frame(width: 30, height: 30)
                    .background { StageSurface(tone: .velvet, radius: 6).opacity(0.85) }
            }
            label.font(.stage(.caption2, weight: .semibold, display: true))
                .foregroundStyle(selected ? TrickoStyle.accent : .white)
                .lineLimit(1).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                .frame(width: 48, height: labelHeight)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        }.frame(width: 48, height: max(52, 34 + labelHeight))
            .contentShape(.interaction, Rectangle())
    }
}

private struct PlayerRailButton: View {
    let artwork: PlayerArtwork
    let title: String
    let accessibilityTitle: String
    var selected = false
    let action: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        Button(action: action) {
            PlayerRailLabel(artwork: artwork, selected: selected) {
                LocalizedText(title)
            }
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: L10n.text(accessibilityTitle, language: AppLanguage.from(locale))))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
