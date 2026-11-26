import SwiftUI
import WebKit

@MainActor
final class AccountAccessFlow: ObservableObject {
    @Published private(set) var busyMessage: String?
    var isBusy: Bool { busyMessage != nil }

    func perform(_ message: String, operation: () async throws -> Void) async throws {
        guard !isBusy else { throw CancellationError() }
        busyMessage = message
        defer { busyMessage = nil }
        await Task.yield()
        try await operation()
    }
}

struct AccountBusyModifier: ViewModifier {
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    func body(content: Content) -> some View {
        content.allowsHitTesting(!accountAccess.isBusy)
            .accessibilityHidden(accountAccess.isBusy)
            .overlay {
                if let message = accountAccess.busyMessage {
                    ZStack {
                        Color.black.opacity(0.42).ignoresSafeArea()
                        StageLoadingIndicator(title: message).padding(24)
                    }.accessibilityAddTraits(.isModal)
                }
            }
    }
}

struct AccountDecisionDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var showsPolicies = false
    var destructive = false
    var dismissOnOutsideTap = false
    var cancel: (() -> Void)? = nil
    let confirm: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var panelBounds: CGRect?

    private enum DialogSpace: Hashable {
        case viewport
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LocalizedText(title).font(.stage(.headline)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    LocalizedText(message).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsPolicies { PolicyLinks() }
                    VStack(spacing: 10) {
                        Button(action: confirm) {
                            LocalizedText(confirmTitle).font(.stage(.subheadline, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(destructive ? TrickoStyle.danger : TrickoStyle.ink)
                                .background { StageSurface(tone: destructive ? .velvet : .gold) }
                        }.buttonStyle(PressStyle())
                        if let cancel { ActionButton(title: "Cancel", primary: false, action: cancel) }
                    }
                }.padding(20).frame(maxWidth: 360)
                    .background { StageSurface(tone: .velvet) }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(DialogSpace.viewport))
                    } action: { bounds in
                        if dismissOnOutsideTap { panelBounds = bounds }
                    }
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color.black.opacity(0.68).ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named(DialogSpace.viewport)).onEnded { tap in
                guard let panelBounds, !panelBounds.isEmpty, !panelBounds.contains(tap.location) else { return }
                cancel?()
            },
            including: dismissOnOutsideTap ? .all : .subviews
        )
        .coordinateSpace(name: DialogSpace.viewport)
        .trickoImmersiveChrome()
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled()
        .onAppear { titleFocused = true }
    }
}

struct PolicyDocument: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

struct PolicyLinks: View {
    var compact = false
    @EnvironmentObject private var api: APIClient
    @State private var document: PolicyDocument?
    var body: some View {
        Group {
            if compact { linkLayout.buttonStyle(PressStyle()) }
            else { linkLayout.buttonStyle(CompactActionStyle()) }
        }.fullScreenCover(item: $document) { PolicyBrowser(document: $0) }
    }
    private var linkLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 16 : 10) { links }
            VStack(alignment: .leading, spacing: compact ? 0 : 10) { links }
        }.font(.stage(.footnote, weight: .medium)).foregroundStyle(TrickoStyle.accent)
    }
    @ViewBuilder private var links: some View {
        if let url = api.configuration.termsURL {
            Button("Terms of Use") { document = PolicyDocument(title: "Terms of Use", url: url) }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
        if let url = api.configuration.privacyURL {
            Button("Privacy Policy") { document = PolicyDocument(title: "Privacy Policy", url: url) }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
    }
}

@MainActor
final class PolicyBrowserState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var requestID = 0
    @Published var canGoBack = false
    @Published var currentURL: URL?
    var retryURL: URL?
    weak var webView: WKWebView?
    func retry() { error = nil; loading = true; requestID += 1 }
    func goBack() { webView?.goBack() }
}

struct PolicyBrowser: View {
    let document: PolicyDocument
    var webSearch = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PolicyReader(document: document, webSearch: webSearch)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                    }
                }
        }
        .trickoImmersiveChrome()
    }
}

private struct PolicyReader: View {
    let document: PolicyDocument
    var webSearch = false
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var state = PolicyBrowserState()

    var body: some View {
        ZStack {
            PolicyWebView(url: document.url, state: state, webSearch: webSearch)
                .allowsHitTesting(!state.loading && state.error == nil)
                .accessibilityHidden(state.loading || state.error != nil)
            if let error = state.error {
                TrickoStyle.background
                ScrollView {
                    EmptyStatePanel(symbol: webSearch ? .search : .link) {
                        EmptyStateCopy(title: "Couldn’t open this page", message: error)
                        Button { state.retry() } label: { LocalizedText("Try again") }
                            .buttonStyle(EmptyStateActionStyle(primary: false))
                    }
                    .frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
                }
            } else if state.loading {
                TrickoStyle.background.opacity(state.currentURL == nil || reduceTransparency ? 1 : 0.80)
                StageLoadingIndicator(title: webSearch ? "Opening page…" : "Opening document…").padding(24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if webSearch || state.canGoBack {
                HStack(spacing: 10) {
                    Button { state.goBack() } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressStyle()).disabled(!state.canGoBack)
                    Text(verbatim: state.currentURL?.host ?? document.url.host ?? "")
                        .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.trailing, 16)
                .trickoGlass(in: Capsule(), fallback: TrickoStyle.surface, interactive: false)
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
        .navigationTitle(Text(verbatim: L10n.text(document.title, language: AppLanguage.from(locale))))
        .navigationBarTitleDisplayMode(.inline)
        .trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
    }
}

struct PolicyWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: PolicyBrowserState
    var webSearch = false
    func makeCoordinator() -> Coordinator { Coordinator(state: state, webSearch: webSearch) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = false
        view.isOpaque = false
        state.webView = view
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.requestID != state.requestID else { return }
        context.coordinator.requestID = state.requestID
        context.coordinator.load(URLRequest(url: state.retryURL ?? url, timeoutInterval: 30), in: view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
        coordinator.state.webView = nil
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: PolicyBrowserState
        let webSearch: Bool
        var requestID: Int?
        private var appNavigationURL: URL?
        init(state: PolicyBrowserState, webSearch: Bool) { self.state = state; self.webSearch = webSearch }
        func load(_ request: URLRequest, in webView: WKWebView) {
            appNavigationURL = request.url
            state.retryURL = request.url
            webView.load(request)
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.loading = true
            state.error = nil
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.currentURL = webView.url
            state.canGoBack = webView.canGoBack
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.loading = false
            state.currentURL = webView.url
            state.canGoBack = webView.canGoBack
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            state.loading = false
            state.error = "The document was interrupted. Please try again."
        }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            state.loading = false
            state.error = "Check your connection and try again."
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.scheme == "https" || (webSearch && url.scheme == "http") || url.absoluteString == "about:blank" else {
                decisionHandler(.cancel)
                return
            }
            guard navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.allow)
                return
            }
            state.retryURL = url
            let isPageLink = webSearch || navigationAction.navigationType == .linkActivated
            if navigationAction.targetFrame == nil ||
                (isPageLink && navigationAction.navigationType != .backForward && appNavigationURL != url) {
                // Load tapped links ourselves so Universal Links also stay in this web view.
                decisionHandler(.cancel)
                load(navigationAction.request, in: webView)
            } else {
                appNavigationURL = nil
                decisionHandler(.allow)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
                state.loading = false
                state.error = "This document is temporarily unavailable. Please try again."
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

struct AccountSettingsSection: View {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    private var unavailable: Bool { accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPreparingAppOpen || ads.isPresenting }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                NavigationLink {
                    LanguagePicker()
                } label: {
                    AccountMenuRow(title: "App language", detail: AppLanguage(rawValue: languageCode)?.nativeName ?? "Follow system")
                }
                .accessibilityIdentifier("account.language")
                if let website = api.configuration.websiteURL {
                    rowDivider
                    NavigationLink {
                        PolicyReader(document: PolicyDocument(title: "Official website", url: website))
                    } label: {
                        AccountMenuRow(title: "Official website", detail: website.host)
                    }
                    .disabled(unavailable)
                    .accessibilityIdentifier("account.officialWebsite")
                }
            }
            .padding(.horizontal, 15)
            .background { StageSurface(tone: .smoke) }
            .buttonStyle(PressStyle())
            if api.configuration.privacyURL != nil || api.configuration.termsURL != nil || ads.privacyOptionsRequired {
                VStack(alignment: .leading, spacing: 3) {
                    LocalizedText("Privacy & terms").font(.stage(.headline))
                        .accessibilityAddTraits(.isHeader)
                    if let url = api.configuration.privacyURL {
                        NavigationLink {
                            PolicyReader(document: PolicyDocument(title: "Privacy Policy", url: url))
                        } label: {
                            AccountMenuRow(title: "Privacy Policy")
                        }
                        rowDivider
                    }
                    if let url = api.configuration.termsURL {
                        NavigationLink {
                            PolicyReader(document: PolicyDocument(title: "Terms of Use", url: url))
                        } label: {
                            AccountMenuRow(title: "Terms of Use")
                        }
                        rowDivider
                    }
                    if ads.privacyOptionsRequired {
                        Button { Task { await ads.privacyOptions() } } label: {
                            AccountMenuRow(title: "Advertising privacy")
                        }.disabled(ads.isPresentingConsent)
                        rowDivider
                    }
                }
                .buttonStyle(PressStyle()).disabled(unavailable)
            }
            if let error = ads.error { ErrorNote(message: error) }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(TrickoStyle.line).accessibilityHidden(true)
    }
}

private struct AccountMenuRow: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let detail {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        rowTitle.fixedSize()
                        Spacer(minLength: 0)
                        LocalizedText(detail).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        rowTitle
                        LocalizedText(detail)
                    }
                }
                .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                rowTitle.frame(maxWidth: .infinity, alignment: .leading)
            }
            Glyph(symbol: .back, size: 11, tint: TrickoStyle.secondary).rotationEffect(.degrees(180))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(.interaction, Rectangle())
    }

    private var rowTitle: some View {
        LocalizedText(title).font(.stage(.subheadline, weight: .medium)).foregroundStyle(TrickoStyle.paper)
    }
}
