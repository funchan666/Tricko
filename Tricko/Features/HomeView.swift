import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    let openPractice: () -> Void
    let openAccount: () -> Void
    @Binding var link: String
    @Binding var channel: ChannelRoute?
    @Binding var searchRequest: LessonSearch?
    @State private var error: String?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingLinkGuide = false
    @State private var showingMagicGuide = false
    @State private var rehearsalSetting: PracticeSetting?
    @State private var showingLink = false
    @State private var pendingLinkSearch: LessonSearch?
    @State private var composerError: String?
    @FocusState private var focused: Bool
    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                lessonFeature
                practiceCard
                MagicGuideEntry(compact: true) { showingMagicGuide = true }
                connection
                recentLinks
                lessonIndex
            }.trickoPage()
        }.trickoScreenBackground()
            .sheet(isPresented: $showingLink, onDismiss: openPendingLesson) {
                VStack(spacing: 0) {
                    SheetHeading(title: "Open a magic lesson") { showingLink = false }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            linkComposer
                            if api.session == nil { ConnectionPanel() }
                        }.trickoPage()
                    }.scrollDismissesKeyboard(.interactively)
                }.trickoScreenBackground()
                    .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
                    .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            }
            .sheet(isPresented: $paywall) { MembershipView() }
            .sheet(isPresented: $showingMagicGuide) { MagicGuideView() }
            .sheet(item: $rehearsalSetting) { setting in RoutinePracticeView(initialSetting: setting) }
            .task(id: request) {
                guard !Task.isCancelled else { return }
                channels = []
                error = nil
                guard !request.links.isEmpty else { return }
                do {
                    let result = try await api.channels(links: request.links)
                    if !Task.isCancelled { channels = result }
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                wordmark.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                membershipButton(inline: true)
                accountButton
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    wordmark.frame(maxWidth: .infinity, alignment: .leading)
                    accountButton
                }
                membershipButton(inline: false).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var wordmark: some View {
        Text(verbatim: "Tricko")
            .font(.stage(.largeTitle, weight: .bold, display: true))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func membershipButton(inline: Bool) -> some View {
        Button { paywall = true } label: {
            LocalizedText(commerce.premium ? "Plus" : "Get Plus")
                .font(.stage(.footnote, weight: .semibold))
                .fixedSize(horizontal: inline, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(TrickoStyle.accent)
                .background { StageSurface(tone: .smoke, radius: 12) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var accountButton: some View {
        Button(action: openAccount) {
            Image("TabMe").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(TrickoStyle.paper)
                .accessibilityHidden(true)
                .frame(width: 44, height: 44)
                .background { StageSurface(tone: .smoke, radius: 12) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey("Open Me and account settings"))
            .accessibilityIdentifier("home.account")
    }

    private var lessonFeature: some View {
        VStack(spacing: 0) {
            Button { searchRequest = LessonSearch(query: "") } label: {
                ZStack(alignment: .bottomLeading) {
                    Color.clear.aspectRatio(2.05, contentMode: .fit).frame(maxHeight: 224)
                        .accessibilityHidden(true)
                    HStack(spacing: 8) {
                        Glyph(symbol: .play, size: 15, tint: TrickoStyle.accent)
                        LocalizedText("Watch lessons").font(.stage(.footnote, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
                    .foregroundStyle(TrickoStyle.paper)
                    .background(TrickoStyle.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                }
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .background {
                    Image("StageHero").resizable().scaledToFill()
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .clipped().contentShape(Rectangle())
            }.buttonStyle(PressStyle()).disabled(searchRequest != nil)
                .accessibilityIdentifier("home.watchLessons")

            Button { showingLink = true } label: {
                HStack(spacing: 12) {
                    Glyph(symbol: .link, size: 20, tint: TrickoStyle.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        LocalizedText("Open a magic lesson").font(.stage(.headline, weight: .semibold))
                        LocalizedText("Lesson link or short code").font(.stage(.caption))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .back, size: 13, tint: TrickoStyle.ink).rotationEffect(.degrees(180))
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 56)
                .foregroundStyle(TrickoStyle.ink)
                .background(TrickoStyle.accent)
                .contentShape(Rectangle())
            }.buttonStyle(PressStyle()).accessibilityIdentifier("home.showLink")
        }
        .background(TrickoStyle.surface)
        .clipShape(.rect(cornerRadius: 20))
    }

    @ViewBuilder private var connection: some View {
        if api.session == nil { ConnectionPanel() }
        if let error {
            MessagePanel(title: "Couldn’t load lesson collections", message: error, actionTitle: "Try again") {
                channelRetry += 1
            }
        }
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    practiceTitle.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    reviewButton(inline: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    practiceTitle
                    reviewButton(inline: false)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(PracticeSetting.allCases) { practiceButton($0, inline: true) }
                }
                VStack(spacing: 8) {
                    ForEach(PracticeSetting.allCases) { practiceButton($0, inline: false) }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
            .foregroundStyle(TrickoStyle.ink)
            .background { StageSurface(tone: .ivory, radius: 18) }
    }

    private var practiceTitle: some View {
        LocalizedText("Practice log").font(.stage(.title2, display: true))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func reviewButton(inline: Bool) -> some View {
        Button(action: openPractice) {
            HStack(spacing: 6) {
                Glyph(symbol: .edit, size: 15, tint: TrickoStyle.paperSecondary)
                LocalizedText("Review practice").font(.stage(.footnote, weight: .semibold))
                    .fixedSize(horizontal: inline, vertical: true)
            }.padding(.vertical, 8).frame(minHeight: 44)
                .foregroundStyle(TrickoStyle.paperSecondary)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.reviewPractice")
    }

    private func practiceButton(_ setting: PracticeSetting, inline: Bool) -> some View {
        Button { rehearsalSetting = setting } label: {
            HStack(spacing: 8) {
                LocalizedText(setting.label).font(.stage(.footnote, weight: .semibold))
                    .fixedSize(horizontal: inline, vertical: true)
                if !inline {
                    Spacer(minLength: 0)
                    Glyph(symbol: .back, size: 12, tint: TrickoStyle.ink).rotationEffect(.degrees(180))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(TrickoStyle.ink)
            .background { StageSurface(tone: .mist, radius: 10) }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityIdentifier("practice.setting.\(setting.rawValue)")
    }

    @ViewBuilder private var lessonIndex: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                LocalizedText("Lesson collections").font(.stage(.title2, display: true))
                    .accessibilityAddTraits(.isHeader)
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

    private func openPendingLesson() {
        focused = false
        composerError = nil
        guard let request = pendingLinkSearch else { return }
        pendingLinkSearch = nil
        searchRequest = request
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Lesson link or short code")
                .font(.stage(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            linkField
            if let composerError { ErrorNote(message: composerError, onPaper: true) }
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
        }.padding(16)
            .background { StageSurface(tone: .ivory, radius: 20) }
            .foregroundStyle(TrickoStyle.ink)
            .onChange(of: link) { _, _ in composerError = nil }
    }

    private var linkHelpButton: some View {
        Button { showingLinkGuide = true } label: {
            LocalizedText("How to").font(.stage(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
                .foregroundStyle(TrickoStyle.paperSecondary)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.linkHelp")
    }

    private func openLessonButton(inline: Bool) -> some View {
        Button(action: resolve) {
            LocalizedText("Open lesson").font(.stage(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: inline, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(canOpenLink ? TrickoStyle.ink : TrickoStyle.paperSecondary)
                .background { StageSurface(tone: canOpenLink ? .gold : .mist, radius: 12) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle(disabledOpacity: 1)).disabled(!canOpenLink)
            .accessibilityIdentifier("home.openLesson")
    }

    private var linkField: some View {
        HStack(spacing: 0) {
            TextField("", text: $link, axis: .vertical)
                .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.ink)
                .tint(TrickoStyle.ink)
                .padding(.leading, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityLabel(LocalizedStringKey("Tricko link or lesson code"))
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
            // Link input and its clear action stay together, including when
            // the outside-tap handler decides whether to dismiss the keyboard.
            .padding(.trailing, link.isEmpty ? 14 : 6)
            .environment(\.layoutDirection, .leftToRight)
            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(TrickoStyle.ink.opacity(focused ? 0.6 : 0.16))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .environment(\.colorScheme, .light)
            .keyboardInputRegion("home-link-input")
    }

    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    @ViewBuilder private var allowanceLabel: some View {
        if api.session != nil {
            LocalizedText(quota.usage == nil ? "Loading…" : commerce.premium || quota.unlimited ? "Unlimited viewing today" : "\(quota.watchesLeft) views left today")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func pasteButton(inline: Bool) -> some View {
        Button(action: pasteCopiedLink) {
            LocalizedText("Paste").font(.stage(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: inline, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: inline ? nil : .infinity, minHeight: 48)
                .foregroundStyle(TrickoStyle.ink)
                .background { StageSurface(tone: .mist, radius: 12) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityIdentifier("home.pasteLink")
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string, text.nilIfBlank != nil else {
            showLinkFailure("Copy a Tricko link or lesson code first, then tap Paste.")
            return
        }
        composerError = nil
        link = text
    }
    @ViewBuilder private var recentLinks: some View {
        let visits = library.history.filter { $0.link.nilIfBlank != nil }
        if !visits.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LocalizedText("Recently opened").font(.stage(.title3, display: true))
                    Spacer()
                    Button("Clear") { library.clearHistory() }
                        .buttonStyle(QuietActionStyle())
                }
                ForEach(visits.prefix(5)) { visit in
                    HStack {
                        Button { link = visit.link; resolve() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: visit.title).font(.stage(.headline)).lineLimit(1)
                                Text(verbatim: visit.link).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).disabled(searchRequest != nil)
                        IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                    }
                }
            }
        }
    }
    private func resolve() {
        guard let text = link.nilIfBlank, searchRequest == nil else { return }
        focused = false
        guard api.session != nil else { showLinkFailure("Your connection is not ready yet. Please try again."); return }
        // Preserve exactly what was entered. Search owns loading, errors and cursor
        // pagination; do not fall back to the old landing-page resolver.
        let request = LessonSearch(query: text)
        if showingLink {
            pendingLinkSearch = request
            showingLink = false
        } else {
            searchRequest = request
        }
    }
    private func showLinkFailure(_ message: String) {
        composerError = message
        showingLink = true
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
    @State private var error: String?
    @State private var child: ChannelRoute?
    @State private var player: PlayerRoute?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: route.title) { dismiss() }
            ScrollView {
                LazyVStack(spacing: 18) {
                    StageArtwork(kind: .notebook, height: 140)
                    if items.isEmpty, !loading, error == nil { MessagePanel(title: "Nothing here yet", message: "This channel has no available videos.") }
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
                    if hasMore { ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) { Task { await load() } } }
                }.padding(22)
            }
        }.trickoScreenBackground().foregroundStyle(.white)
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 54) }
    }
    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.channelPage(link: route.link, page: page)
            var seen = Set(items.map(\.stableID))
            items += result.list.filter { $0.name?.nilIfBlank != nil && !$0.stableID.isEmpty && seen.insert($0.stableID).inserted }
            hasMore = page * 20 < result.total && !result.list.isEmpty
            page += 1
        } catch { self.error = error.localizedDescription }
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
                    StageArtwork(kind: .cards, height: 150)
                    FeatureRow(symbol: .link, title: "1. Copy a Tricko link", detail: "Use a lesson link or code shared through Tricko.")
                    FeatureRow(symbol: .search, title: "2. Paste it above", detail: "Tap Paste or enter the lesson code exactly as received. Codes are case-sensitive.")
                    FeatureRow(symbol: .play, title: "3. Open and watch", detail: "Tap Open lesson to find matching lessons, then swipe to watch.")
                    LocalizedText("No results? Check your input, or ask the sender for a new link.")
                        .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.trickoPage()
            }
        }.trickoScreenBackground().foregroundStyle(.white)
    }
}
