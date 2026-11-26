import SwiftUI
import OSLog

@main
struct TrickoApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @Environment(\.scenePhase) private var appPhase
    @State private var systemLanguage = AppLanguage.systemLanguage()
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? systemLanguage }
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var offline: OfflineStore
    @StateObject private var ads: RewardedAds
    @StateObject private var accountAccess = AccountAccessFlow()
    init() {
        let api = APIClient()
        let quota = QuotaStore()
        _api = StateObject(wrappedValue: api)
        _library = StateObject(wrappedValue: LibraryStore())
        _quota = StateObject(wrappedValue: quota)
        let commerce = CommerceStore(api: api, quota: quota)
        _commerce = StateObject(wrappedValue: commerce)
        _offline = StateObject(wrappedValue: OfflineStore(api: api, quota: quota, commerce: commerce))
        _ads = StateObject(wrappedValue: RewardedAds())
    }
    var body: some Scene {
        WindowGroup {
            TrickoStartupHost().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads).environmentObject(offline)
                .environmentObject(accountAccess)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.direction)
                .font(.stage(.body))
                .preferredColorScheme(.dark).tint(TrickoStyle.accent)
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    systemLanguage = AppLanguage.systemLanguage()
                }
                .onChange(of: appPhase) { _, phase in
                    if phase == .active { systemLanguage = AppLanguage.systemLanguage() }
                }
        }
    }
}

struct TrickoStartupHost: View {
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var startupBegan = ContinuousClock.now

    var body: some View {
        ZStack {
            TrickoRootView()
                .allowsHitTesting(finished)
                .accessibilityHidden(!finished)
            if !finished {
                TrickoStartupView().transition(.opacity)
            }
        }.trickoScreenBackground()
        .task(id: scenePhase) {
            guard scenePhase == .active, !finished else { return }
            ads.beginStartup(commerce: commerce, accountAccess: accountAccess)
        }
        .onReceive(ads.$startupFinished) { complete in
            if complete, !finished {
                Logger(subsystem: TrickoConfiguration.logSubsystem, category: "Startup")
                    .info("Home became interactive after \(startupBegan.duration(to: .now).description, privacy: .public)")
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ads.didEnterBackground() }
            if phase == .active {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct TrickoStartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var loadingMark: some View {
        Image("TrickoLoadingMark")
            .resizable().scaledToFill().frame(width: 40, height: 5).clipped()
    }

    var body: some View {
        Image("TrickoLaunchMark")
            .resizable().scaledToFit().frame(width: 108, height: 108)
            .overlay(alignment: .bottom) {
                Group {
                    if reduceMotion || scenePhase != .active {
                        loadingMark
                    } else {
                        loadingMark.phaseAnimator([false, true]) { content, dimmed in
                            content.opacity(dimmed ? 0.5 : 1)
                        } animation: { _ in .easeInOut(duration: 0.75) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .trickoGlass(in: Capsule(), tint: TrickoStyle.coolAccent.opacity(0.10),
                             fallback: TrickoStyle.surface, interactive: false)
                .offset(y: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: L10n.text("Loading…")))
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

private enum TrickoTab: Int, CaseIterable, Hashable {
    case home = 0
    case library = 3
    case tools = 2

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .tools: "Tools"
        }
    }
    var glyph: TrickoGlyph {
        switch self {
        case .home: .feed
        case .library: .folder
        case .tools: .settings
        }
    }
}

struct TrickoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @SceneStorage("root.tab") private var legacyTabRaw: Int?
    @SceneStorage("home.linkDraft") private var linkDraft = ""
    @AppStorage("tricko.root.tab") private var tabRaw: Int?
    @AppStorage("tricko.library.category") private var libraryFilter = "Imports"
    @State private var showingAccount = false
    @State private var libraryEditor: PracticeRecording?
    @State private var channel: ChannelRoute?
    @State private var searchRequest: LessonSearch?
    @State private var downloadsAfterLesson = false

    private var selectedTab: TrickoTab {
        (tabRaw ?? legacyTabRaw).flatMap(TrickoTab.init(rawValue:)) ?? .home
    }

    private var tab: Binding<TrickoTab> {
        Binding(get: { selectedTab }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        navigation
            .foregroundStyle(TrickoStyle.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = library.error {
                    HStack {
                        LocalizedText(message).font(.stage(.subheadline))
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background { StageSurface(tone: .velvet) }.padding()
                } else if offline.completedDownloadID != nil {
                    DownloadCompletionNotice().padding(.top, 8)
                }
            }
            .fullScreenCover(isPresented: $showingAccount) {
                AccountView()
                    .modifier(AccountBusyModifier())
            }
            .fullScreenCover(item: $channel, onDismiss: finishLessonDismissal) { ChannelView(route: $0) }
            .fullScreenCover(item: $libraryEditor) { EditorSheet(initialMovie: $0) }
            .fullScreenCover(item: $searchRequest, onDismiss: finishLessonDismissal) { request in
                DiscoverView(initialSearch: request.query, onExit: { searchRequest = nil }, onSearchResult: { query, clip in
                    guard query.nilIfBlank != nil else { return }
                    library.record(link: query, title: clip.title)
                })
            }
            .onChange(of: legacyTabRaw, initial: true) { _, previous in
                if tabRaw == nil, let previous, TrickoTab(rawValue: previous) != nil {
                    tabRaw = previous
                }
            }
            .onChange(of: library.downloadsRequest) { _, request in
                guard request != nil else { return }
                if channel != nil || searchRequest != nil {
                    downloadsAfterLesson = true
                    channel = nil
                    searchRequest = nil
                } else if !downloadsAfterLesson {
                    showDownloads()
                }
            }
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                if !commerce.rightsVerified || commerce.release == nil { await commerce.refresh() }
                await offline.resumePending()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded() }
            }
            .modifier(AccountBusyModifier())
    }

    @ViewBuilder private var navigation: some View {
        if #available(iOS 26.0, *) {
            glassTabs.tabBarMinimizeBehavior(.never)
        } else {
            labeledTabs
        }
    }

    @available(iOS 26.0, *)
    private var glassTabs: some View {
        TabView(selection: tab) {
            ForEach(TrickoTab.allCases, id: \.self) { item in
                Tab(value: item) {
                    tabPage(item)
                } label: {
                    Image(item.glyph.asset).renderingMode(.template)
                }
                .accessibilityLabel(tabTitle(item))
                .accessibilityIdentifier("tab.\(item.title.lowercased())")
            }
        }
        .trickoScreenBackground()
    }

    private var labeledTabs: some View {
        TabView(selection: tab) {
            Group {
                ForEach(TrickoTab.allCases, id: \.self) { item in
                    tabPage(item).tabItem {
                        Label { tabTitle(item) } icon: {
                            Image(item.glyph.asset).renderingMode(.template)
                        }.accessibilityIdentifier("tab.\(item.title.lowercased())")
                    }.tag(item)
                }
            }
            .toolbarBackground(TrickoStyle.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
        }
        .trickoScreenBackground()
    }

    @ViewBuilder private func tabPage(_ item: TrickoTab) -> some View {
        switch item {
        case .home:
            HomeView(openAccount: { showingAccount = true }, openVideo: openVideo,
                     showImports: showImports, link: $linkDraft, channel: $channel, searchRequest: $searchRequest)
        case .tools:
            ToolsView(openSettings: { showingAccount = true })
        case .library:
            LibraryView(edit: openVideo,
                        watchLessons: { searchRequest = LessonSearch(query: "") },
                        isActive: selectedTab == .library, filter: $libraryFilter)
        }
    }

    private func tabTitle(_ item: TrickoTab) -> Text {
        Text(verbatim: L10n.text(item.title, language: AppLanguage.from(locale)))
    }

    private func openVideo(_ movie: PracticeRecording) {
        guard libraryEditor == nil else { return }
        libraryEditor = movie
    }

    private func finishLessonDismissal() {
        guard downloadsAfterLesson else { return }
        downloadsAfterLesson = false
        showDownloads()
    }

    private func showDownloads() {
        libraryFilter = "Downloads"
        tab.wrappedValue = .library
    }

    private func showImports() {
        libraryFilter = "Imports"
        tab.wrappedValue = .library
    }
}

struct ConnectionPanel: View {
    var showsPolicyLinks = true
    @EnvironmentObject private var api: APIClient
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            if let error {
                EmptyStatePanel(symbol: .link) {
                    EmptyStateCopy(title: "Let’s reconnect.", message: error)
                    Button { attempt += 1 } label: { LocalizedText("Try again") }
                        .buttonStyle(EmptyStateActionStyle(primary: false))
                        .disabled(connecting)
                }
            } else {
                StageLoadingIndicator(title: "Setting up your table…")
            }
            if showsPolicyLinks { PolicyLinks() }
        }
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
        .task(id: attempt) {
            guard api.session == nil else { return }
            connecting = true
            error = nil
            defer { connecting = false }
            do { try await api.prepareVisitor() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
