import SwiftUI
import StoreKit

struct PlusEntryButton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let active: Bool
    var compact = false
    let action: () -> Void

    private var title: String {
        active ? (compact ? "Plus" : "Manage membership") : "Get Plus"
    }

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    LocalizedText(title).font(.stage(.footnote, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(TrickoStyle.accent)
                        .trickoGlass(in: Capsule())
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            artwork
                            copy.frame(minWidth: 136, idealWidth: typeSize.isAccessibilitySize ? 280 : 160,
                                       maxWidth: .infinity, alignment: .leading)
                            arrow
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            artwork
                            HStack(spacing: 8) { copy; arrow }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(TrickoStyle.ink)
                    .background { StageSurface(tone: .ivory, radius: 16) }
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var artwork: some View {
        StagePhoto(asset: "VideoPlusPhoto")
            .frame(width: 60, height: 52)
            .clipShape(.rect(cornerRadius: 9))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            LocalizedText(title).font(.stage(.title3, weight: .bold, display: true))
            LocalizedText(active ? "Plus active" : "Video exports, editing presets and no opening ads.")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.paperSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var arrow: some View {
        Glyph(symbol: .back, size: 12, tint: TrickoStyle.accent)
            .rotationEffect(.degrees(180))
            .frame(width: 32, height: 32)
            .background { StageSurface(tone: .ink, radius: 10) }
    }
}

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
    var reviewPresetsRequired = false
    @Environment(\.locale) private var locale
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var priceRequest = 0
    @State private var attemptedPurchaseAction = false
    @State private var purchaseTask: Task<Void, Never>?
    @State private var rewardTask: Task<Void, Never>?
    @State private var requestedReward = false
    @State private var acknowledgedLuckyReward = false

    private struct Plan: Identifiable {
        let entry: CommerceConfiguration.Product
        let product: SKProduct?
        var id: String { entry.id }
    }

    private var plans: [Plan] {
        (commerce.policy?.products ?? []).map { entry in
            Plan(entry: entry, product: commerce.products.first { $0.productIdentifier == entry.id })
        }
    }
    private var selectedPlan: Plan? {
        plans.first(where: { $0.id == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }
    private var entryMessage: String? {
        if reviewPresetsRequired { return "Review presets are included with Plus." }
        if exportRequired { return "Export is included with Plus." }
        return nil
    }

    var body: some View {
        StagePage(asset: "VideoPlusPhoto", minHeight: 204, maxHeight: 258, photoOpacity: 1) { _ in
            membershipIntro
        } content: {
            subscriptionOptions
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .foregroundStyle(TrickoStyle.paper)
        .task { await commerce.refresh() }
        .task(id: priceRequest) { await commerce.loadPlans() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
        .onDisappear {
            purchaseTask?.cancel(); purchaseTask = nil
            if !ads.isPresenting { cancelRewardRequest() }
        }
        .onChange(of: ads.completedReward) { _, completion in
            if requestedReward, completion != nil { dismiss() }
        }
        .interactiveDismissDisabled(purchasing || ads.isPresenting)
        .fullScreenCover(item: $ads.luckyReward, onDismiss: {
            if acknowledgedLuckyReward && requestedReward { dismiss() }
        }) { reward in
            LuckyRewardView(message: reward.message) {
                acknowledgedLuckyReward = true
                ads.luckyReward = nil
            }
                .presentationBackground(.clear)
        }
    }

    private var subscriptionOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let entryMessage, !commerce.premium {
                LocalizedText(entryMessage)
                    .font(.stage(.subheadline, weight: .semibold)).foregroundStyle(TrickoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if commerce.premium {
                activeMembership
            } else {
                if api.session == nil { ConnectionPanel() }
                if !plans.isEmpty { planPicker }
                if let error = commerce.plansError {
                    ErrorNote(message: error)
                }
            }
            renewalDisclosure
            if !commerce.premium { purchaseAction }
            restoreLink
            if attemptedPurchaseAction {
                if let error = commerce.error { ErrorNote(message: error) }
                if let message = commerce.message {
                    LocalizedText(message).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.accent)
                }
            }
            PolicyLinks(compact: true)
            if rewardKind == nil { plusBenefits }
            if entryMessage == nil, !commerce.premium, api.session != nil { rewardOption }
            if rewardKind != nil { plusBenefits }
        }
    }

    private var closeButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                cancelRewardRequest()
                dismiss()
            } label: {
                Glyph(symbol: .close, size: 16, tint: TrickoStyle.paper)
                    .frame(width: 44, height: 44)
                    .trickoGlass(in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(PressStyle())
                .accessibilityLabel(LocalizedStringKey("Close"))
                .disabled(purchasing || ads.isPresenting)
        }.pageHorizontalMargins().padding(.top, 12)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        guard let plan = selectedPlan else { return "Subscription unavailable" }
        return plan.product == nil ? "Check Apple price" : "Subscribe"
    }

    private var membershipIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Plus")
                .font(.stage(.largeTitle, weight: .heavy))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            LocalizedText("Video exports, editing presets and no opening ads.")
                .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.paper.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plusBenefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            LocalizedText("Included with Plus").font(.stage(.title3, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                benefit(.edit, "Video and audio exports", "Share edited videos as MP4 or save the audio as M4A.", onPaper: true)
                Divider().overlay(TrickoStyle.ink.opacity(0.16))
                benefit(.settings, "Review presets", "Apply slow-motion presets or reuse your saved settings in the video editor.", onPaper: true)
            }
            .padding(16)
            .background { StageSurface(tone: .ivory, radius: 16) }
            benefit(.exit, "Skip opening ads", "Open or return to the app without an opening ad.")
            benefit(.play, "Unlimited lesson views", "Watch lessons without using a daily view allowance.")
            benefit(.download, "Unlimited offline downloads", "Download supported lessons for offline viewing without a daily limit.")
        }
        .padding(.top, 10)
    }

    private func benefit(_ symbol: TrickoGlyph, _ title: String, _ description: String, onPaper: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(symbol: symbol, size: 19, tint: onPaper ? TrickoStyle.ink : TrickoStyle.accent)
                .frame(width: 30, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.stage(.subheadline, weight: .semibold))
                    .foregroundStyle(onPaper ? TrickoStyle.ink : TrickoStyle.paper)
                LocalizedText(description).font(.stage(.footnote))
                    .foregroundStyle(onPaper ? TrickoStyle.paperSecondary : TrickoStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var activeMembership: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText("Your membership is active")
                .font(.stage(.headline, weight: .semibold)).foregroundStyle(TrickoStyle.accent)
            if let expiration = commerce.expiration {
                LocalizedText("Access through %@.", expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                    .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { StageSurface(tone: .smoke, radius: 16, border: TrickoStyle.accent.opacity(0.45)) }
    }

    private var planPicker: some View {
        VStack(spacing: 8) {
            ForEach(plans) { planOption($0) }
        }
    }

    private func planOption(_ plan: Plan) -> some View {
        let selected = selectedPlan?.id == plan.id
        let price = plan.product.map { commerce.price($0) } ?? "USD \(plan.entry.displayPriceUSD)"
        let period = plan.product.map { commerce.period($0, locale: locale) }
        return Button { selectedID = plan.id } label: {
            HStack(spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        LocalizedText(plan.entry.label).font(.stage(.headline, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        planPrice(price, period: period, alignment: .trailing, onPaper: selected, intrinsicWidth: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        LocalizedText(plan.entry.label).font(.stage(.headline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        planPrice(price, period: period, alignment: .leading, onPaper: selected)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Glyph(symbol: .saved, size: 16, tint: TrickoStyle.ink)
                    .opacity(selected ? 1 : 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .foregroundStyle(selected ? TrickoStyle.ink : TrickoStyle.paper)
            .background { StageSurface(tone: selected ? .ivory : .smoke, radius: 16) }
            .contentShape(.rect(cornerRadius: 16))
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(plan.id)")
    }

    private func planPrice(_ price: String, period: String?, alignment: HorizontalAlignment, onPaper: Bool,
                            intrinsicWidth: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                .font(.stage(.title3, weight: .bold)).monospacedDigit()
            Group {
                if let period {
                    LocalizedText("Billed every %@", period)
                } else {
                    LocalizedText("US reference price")
                }
            }
            .font(.stage(.caption))
            .foregroundStyle(onPaper ? TrickoStyle.paperSecondary : TrickoStyle.secondary)
        }.fixedSize(horizontal: intrinsicWidth, vertical: true)
    }

    private var renewalDisclosure: some View {
        LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
            .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseAction: some View {
        Button(action: subscribe) {
            LocalizedText(purchaseButtonTitle).font(.stage(.headline, weight: .semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 51)
                .foregroundStyle(TrickoStyle.ink)
                .background(TrickoStyle.accent, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(PressStyle())
            .disabled(interactionLocked || selectedPlan == nil)
            .accessibilityIdentifier("membership.subscribe")
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        guard plan.product != nil else { priceRequest += 1; return }
        attemptedPurchaseAction = true
        purchaseTask = Task {
            await commerce.purchase(planID: plan.id)
            purchaseTask = nil
        }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Or, keep it free").font(.stage(.headline))
            ForEach(rewardKind.map { [$0] } ?? AllowanceKind.allCases) { kind in
                if quota.canRequestReward(for: kind, premium: commerce.premium) {
                    LocalizedText(quota.rewardSummary(for: kind)).font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                    ActionButton(title: kind == .watch ? "Watch an ad for views" : "Watch an ad for downloads",
                                 primary: false, busy: ads.busy || ads.isPresenting) {
                        requestedReward = true
                        rewardTask = Task { await ads.watch(commerce: commerce, quota: quota, kind: kind) }
                    }.disabled(purchasing || ads.isPreparingAppOpen || ads.busy || ads.isPresenting)
                }
            }
            if ads.busy {
                HStack(spacing: 12) {
                    Image("TrickoLoadingMark").resizable().scaledToFit().frame(width: 28, height: 5)
                        .phaseAnimator([false, true]) { mark, faded in
                            mark.opacity(reduceMotion || scenePhase != .active ? 1 : (faded ? 0.35 : 1))
                        } animation: { _ in
                            reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
                        }
                        .accessibilityHidden(true)
                    LocalizedText("Loading ad…").font(.stage(.footnote))
                    Spacer(minLength: 12)
                    Button("Cancel") { cancelRewardRequest() }
                        .buttonStyle(CompactActionStyle())
                }
            }
            LocalizedText(quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
            LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads today" : "\(quota.downloadsLeft) downloads left today")
            AllowanceResetText()
            LocalizedText("Ad rewards unlock when the corresponding allowance runs out.")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = ads.error { ErrorNote(message: error) }
            if let error = quota.error { ErrorNote(message: error) }
            if let message = ads.message {
                LocalizedText(message).font(.stage(.footnote)).foregroundStyle(TrickoStyle.accent)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(TrickoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func cancelRewardRequest() {
        rewardTask?.cancel()
        rewardTask = nil
        ads.cancelRewardLoading()
    }

    private var restoreLink: some View {
        Button {
            attemptedPurchaseAction = true
            commerce.restore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.stage(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minHeight: 44)
                .foregroundStyle(TrickoStyle.accent)
                .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle())
            .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Me") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let session = api.session {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                accountIdentity(session.userId.value)
                                Spacer(minLength: 16)
                                accountStatus
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                accountIdentity(session.userId.value)
                                accountStatus
                            }
                        }
                        membershipCard
                        allowance
                    } else { ConnectionPanel() }
                    AccountSettingsSection()
                    LocalizedText("Version \(api.configuration.version)")
                        .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 4)
                }.trickoPage()
            }
        }.trickoScreenBackground().foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private func accountIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LocalizedText("Your practice space").font(.stage(.headline)).foregroundStyle(TrickoStyle.paper)
            LocalizedText("ID · \(id)").font(.caption.monospaced()).foregroundStyle(TrickoStyle.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStatus: some View {
        LocalizedText(commerce.premium ? "Plus active" : "Free plan")
            .font(.stage(.caption, weight: .semibold))
            .foregroundStyle(commerce.premium ? TrickoStyle.accent : TrickoStyle.secondary)
    }

    private var membershipCard: some View {
        PlusEntryButton(active: commerce.premium) { paywall = true }
            .disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText("Today").font(.stage(.headline))
                Spacer()
                if !commerce.premium {
                    Button { paywall = true } label: { LocalizedText("View options") }
                        .font(.stage(.footnote, weight: .semibold)).foregroundStyle(TrickoStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel(Text(verbatim: L10n.text("View options for more views and downloads",
                                                                     language: AppLanguage.from(locale))))
                }
            }
            HStack(alignment: .top, spacing: 20) {
                balance(value: commerce.premium || quota.unlimited ? "Unlimited" : "\(quota.watchesLeft)", label: "Views left")
                balance(value: commerce.premium || quota.downloadsUnlimited ? "Unlimited" : "\(quota.downloadsLeft)", label: "Downloads left")
            }
            if commerce.premium {
                LocalizedText("Included with your membership").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
            } else { AllowanceResetText() }
        }
    }

    private func balance(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(value).font(value == "Unlimited" ? .headline : .title.weight(.semibold))
                .monospacedDigit().foregroundStyle(TrickoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(label).font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LuckyRewardView: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    StagePhoto(asset: "ArtPropCase").frame(width: 112, height: 80)
                        .clipShape(.rect(cornerRadius: 12))
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .accessibilityHidden(true)
                    LocalizedText("A little luck, on us").font(.stage(.headline)).foregroundStyle(.white)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Keep exploring", action: dismiss)
                }.padding(20).frame(maxWidth: 360)
                    .background(TrickoStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .trickoImmersiveChrome()
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}


struct AllowanceResetText: View {
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = QuotaStore.nextReset(after: context.date)
            LocalizedText("Resets %@ (local time)", localTime(next))
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}
