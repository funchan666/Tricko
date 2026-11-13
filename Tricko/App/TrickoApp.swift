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

// Keeps the splash visible during the bounded cold-start ad opportunity.
// Guest authentication prepares configuration and opens the app directly.
// Fold/unfold and display changes resize this one scene: they never restart
// login, re-count views or trigger another app-open opportunity.
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
            Color("LaunchBackground").ignoresSafeArea()
            // Mount once so local content and authentication prepare while the
            // bounded app-open opportunity runs, without rebuilding navigation.
            TrickoRootView()
                .allowsHitTesting(finished)
                .accessibilityHidden(!finished)
            if !finished {
                TrickoStartupView().transition(.opacity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !finished else { return }
            ads.beginStartup(commerce: commerce, accountAccess: accountAccess)
        }
        .onReceive(ads.$startupFinished) { complete in
            if complete, !finished {
                Logger(subsystem: "com.tricko.video", category: "Startup")
                    .info("Home became interactive after \(startupBegan.duration(to: .now).description, privacy: .public)")
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ads.didEnterBackground() }
            if phase == .active, finished {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct TrickoStartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Image("TrickoLaunchMark")
            .resizable().scaledToFit().frame(width: 108, height: 108)
            .overlay(alignment: .bottom) {
                Image("TrickoLoadingMark")
                    .resizable().scaledToFill().frame(width: 40, height: 5).clipped()
                    .phaseAnimator([false, true]) { content, dimmed in
                        content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.35 : 1))
                    } animation: { _ in
                        reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
                    }
                    .offset(y: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: L10n.text("Tricko is starting")))
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

enum TrickoTab: Int, CaseIterable, Hashable {
    case home, discover, tools, library, me
    var name: String { ["Home", "Discover", "Practice", "Library", "Me"][rawValue] }
    // Original single-colour template artwork; the system tab bar tints it and,
    // on iPhone Duo, lays the bar out vertically with title + image.
    var artwork: String { ["TabHome", "TabDiscover", "TabPractice", "TabLibrary", "TabMe"][rawValue] }
}

struct TrickoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    // Scene-level state survives fold/unfold and display changes.
    @SceneStorage("root.tab") private var tabRaw = TrickoTab.home.rawValue
    @SceneStorage("home.linkDraft") private var linkDraft = ""
    @State private var editing: PracticeRecording?
    @State private var libraryFilter = "Saved"
    private var tab: Binding<TrickoTab> {
        Binding(get: { TrickoTab(rawValue: tabRaw) ?? .home }, set: { tabRaw = $0.rawValue })
    }
    var body: some View {
        TabView(selection: tab) {
            NavigationStack {
                HomeView(openAccount: { tab.wrappedValue = .me }, discover: { tab.wrappedValue = .discover },
                         openTools: { tab.wrappedValue = .tools }, link: $linkDraft)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { tabLabel(.home) }.tag(TrickoTab.home)

            NavigationStack {
                Group {
                    // Mount the feed only while selected so playback, preloading and
                    // view counting never run on a hidden tab.
                    if tab.wrappedValue == .discover {
                        DiscoverView(onExit: { tab.wrappedValue = .home })
                    } else { TrickoStyle.background.ignoresSafeArea() }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Color.black, for: .tabBar)
            .tabItem { tabLabel(.discover) }.tag(TrickoTab.discover)

            NavigationStack { ToolsView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { tabLabel(.tools) }.tag(TrickoTab.tools)

            NavigationStack {
                LibraryView(edit: { editing = $0 }, filter: $libraryFilter).toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { tabLabel(.library) }.tag(TrickoTab.library)

            NavigationStack { AccountView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { tabLabel(.me) }.tag(TrickoTab.me)
        }
        .toolbarBackground(TrickoStyle.background, for: .tabBar)
        .foregroundStyle(TrickoStyle.paper)
        .sheet(item: $editing) { EditorSheet(initialMovie: $0) }
        .overlay(alignment: .top) {
            if tab.wrappedValue != .discover { DownloadCompletionNotice().padding(.top, 8) }
        }
        .task(id: library.downloadsRequest) {
            guard library.downloadsRequest != nil else { return }
            // Full-screen players dismiss first; then move the underlying tab.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            editing = nil
            libraryFilter = "Downloads"
            tab.wrappedValue = .library
        }
        .task(id: api.session?.userId.value) {
            guard api.session != nil else { return }
            if !commerce.rightsVerified || commerce.release == nil { await commerce.refresh() }
            await offline.resumePending()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { quota.resetIfNeeded() }
        }
        .overlay(alignment: .top) {
            if let message = library.error {
                HStack {
                    LocalizedText(message).font(.stage(.subheadline))
                    IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                }.padding(14).background(TrickoStyle.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding()
            }
        }
        .modifier(AccountBusyModifier())
    }
    private func tabLabel(_ item: TrickoTab) -> some View {
        Label {
            Text(verbatim: L10n.display(item.name, language: AppLanguage.from(locale)))
        } icon: {
            Image(item.artwork).renderingMode(.template)
        }
        .accessibilityIdentifier("tab.\(item.name.lowercased())")
    }
}

// A network recovery surface, not a second login or consent gate.
struct ConnectionPanel: View {
    @EnvironmentObject private var api: APIClient
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            StageArtwork(kind: .hat, height: 170)
            if let error {
                MessagePanel(title: "Let’s reconnect.", message: error)
                ActionButton(title: "Try again", busy: connecting) { attempt += 1 }
            } else {
                AccountLoadingIndicator(title: "Setting up your table…")
            }
            PolicyLinks()
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
