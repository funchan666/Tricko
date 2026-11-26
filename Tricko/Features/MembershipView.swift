import SwiftUI
import StoreKit

struct PlusEntryButton: View {
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
                        .trickoGlass(in: Capsule(), tint: TrickoStyle.accent.opacity(0.18))
                } else {
                    HStack(spacing: 12) {
                        copy
                        Glyph(symbol: .back, size: 12, tint: TrickoStyle.accent)
                            .rotationEffect(.degrees(180))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .foregroundStyle(TrickoStyle.paper)
                    .trickoGlass(in: .rect(cornerRadius: 18), tint: TrickoStyle.accent.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            LocalizedText(title).font(.stage(.title3, weight: .bold, display: true))
            LocalizedText(active ? "Plus active" : "No daily viewing or download limits")
                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

struct MembershipView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var priceRequest = 0
    @State private var purchaseAction: PurchaseAction?
    @State private var purchaseTask: Task<Void, Never>?

    private enum PurchaseAction {
        case subscribe, restore
    }

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
    private var restoring: Bool { purchaseAction == .restore && commerce.busy }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }
    private var purchaseFeedback: String? {
        if purchaseAction != nil, let message = commerce.error ?? commerce.message { return message }
        return commerce.premium ? nil : commerce.plansError
    }

    var body: some View {
        GeometryReader { viewport in
            let plansSideBySide = viewport.size.width >= 360 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                header
                ScrollViewReader { scroll in
                    ScrollView {
                        subscriptionOptions(plansSideBySide: plansSideBySide)
                            .trickoPage()
                    }
                    .onChange(of: purchaseFeedback) { _, feedback in
                        if feedback != nil, purchaseAction != nil || priceRequest > 0 {
                            scroll.scrollTo("membership.feedback", anchor: .bottom)
                        }
                    }
                }
                if !commerce.premium { purchaseBar }
            }
        }
        .trickoScreenBackground()
        .foregroundStyle(TrickoStyle.paper)
        .task { await commerce.refresh() }
        .task(id: priceRequest) { await commerce.loadPlans() }
        .onDisappear {
            purchaseTask?.cancel()
            purchaseTask = nil
        }
        .interactiveDismissDisabled(purchasing || ads.isPresenting)
    }

    private func subscriptionOptions(plansSideBySide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if commerce.premium {
                activeMembership
            } else if !plans.isEmpty {
                planPicker(sideBySide: plansSideBySide)
            }
            if let purchaseFeedback {
                Group {
                    if purchaseAction != nil, commerce.error == nil, commerce.message != nil {
                        LocalizedText(purchaseFeedback).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.accent)
                    } else if !commerce.premium, plans.isEmpty, purchaseFeedback == commerce.plansError {
                        EmptyStatePanel(symbol: .saved) {
                            EmptyStateCopy(title: "Subscription unavailable", message: purchaseFeedback)
                        }
                    } else {
                        ErrorNote(message: purchaseFeedback)
                    }
                }
                .id("membership.feedback")
            }
            plusBenefits
            if !commerce.premium { renewalDisclosure }
            VStack(alignment: .leading, spacing: 0) {
                restoreLink
                if api.session == nil, !commerce.premium {
                    ConnectionPanel(showsPolicyLinks: false).padding(.vertical, 14)
                }
                PolicyLinks(compact: api.session != nil || commerce.premium)
                    .disabled(purchasing || ads.isPresenting)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            LocalizedText("Plus")
                .font(.stage(.largeTitle, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                Glyph(symbol: .close, size: 16, tint: TrickoStyle.paper)
                    .frame(width: 44, height: 44)
                    .trickoGlass(in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(PressStyle())
                .accessibilityLabel(LocalizedStringKey("Close"))
                .disabled(purchasing || ads.isPresenting)
        }
        .pageHorizontalMargins()
        .padding(.vertical, 10)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    private var purchaseActivityTitle: String? {
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy && !restoring { return "Confirming your purchase…" }
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if purchaseTask != nil { return "Preparing your subscription…" }
        return nil
    }

    private var purchaseButtonTitle: String {
        guard let plan = selectedPlan else { return "Subscription unavailable" }
        return plan.product == nil ? "Check Apple price" : "Subscribe"
    }

    private var plusBenefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedText("Included with Plus").font(.stage(.headline, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                benefit(.exit, "Skip opening ads")
                benefit(.play, "No daily viewing or download limits")
            }
            .padding(12)
            .background { StageSurface(tone: .smoke) }
        }
    }

    private func benefit(_ symbol: TrickoGlyph, _ title: String) -> some View {
        HStack(spacing: 10) {
            Glyph(symbol: symbol, size: 16, tint: TrickoStyle.coolAccent)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            LocalizedText(title).font(.stage(.subheadline, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func planPicker(sideBySide: Bool) -> some View {
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                               : AnyLayout(VStackLayout(spacing: 8))
        return TrickoGlassGroup {
            layout {
                ForEach(plans) { planOption($0, sideBySide: sideBySide) }
            }
        }
    }

    private func planOption(_ plan: Plan, sideBySide: Bool) -> some View {
        let selected = selectedPlan?.id == plan.id
        let price = plan.product.map { commerce.price($0) } ?? "USD \(plan.entry.displayPriceUSD)"
        let period = plan.product.map { commerce.period($0, locale: locale) }
        let title = L10n.text(plan.entry.label, language: AppLanguage.from(locale))
        let planLabel = Text(verbatim: title).font(.stage(.subheadline, weight: .semibold))
        let stackedDetails = VStack(alignment: .leading, spacing: 6) {
            planLabel.fixedSize(horizontal: false, vertical: true)
            planPrice(price, period: period, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)

        return Button { selectedID = plan.id } label: {
            HStack(alignment: sideBySide ? .top : .center, spacing: 8) {
                if sideBySide {
                    stackedDetails
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            planLabel.fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            planPrice(price, period: period, alignment: .trailing, intrinsicWidth: true)
                        }
                        stackedDetails
                    }
                }
                Glyph(symbol: .saved, size: 16, tint: TrickoStyle.accent)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: sideBySide ? 112 : 64, alignment: sideBySide ? .topLeading : .leading)
            .foregroundStyle(TrickoStyle.paper)
            .trickoGlass(in: .rect(cornerRadius: 18), tint: selected ? TrickoStyle.accent.opacity(0.22) : nil)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(TrickoStyle.accent.opacity(0.75), lineWidth: 1.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .contentShape(.rect(cornerRadius: 18))
        }.buttonStyle(PressStyle(disabledOpacity: 0.9)).disabled(interactionLocked)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(plan.id)")
    }

    private func planPrice(_ price: String, period: String?, alignment: HorizontalAlignment,
                            intrinsicWidth: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                .font(.stage(.title2, weight: .bold)).monospacedDigit()
            Group {
                if let period {
                    LocalizedText("Billed every %@", period)
                } else {
                    LocalizedText("US reference price")
                }
            }
            .font(.stage(.caption))
            .foregroundStyle(TrickoStyle.secondary)
        }.fixedSize(horizontal: intrinsicWidth, vertical: true)
    }

    private var renewalDisclosure: some View {
        LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
            .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(TrickoStyle.line).frame(height: 1)
                .accessibilityHidden(true)
            Button(action: subscribe) {
                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        if purchaseActivityTitle != nil { StageActivityMark(size: 18) }
                        LocalizedText(purchaseActivityTitle ?? purchaseButtonTitle)
                            .font(.stage(.headline, weight: .semibold))
                    }
                    if let plan = selectedPlan, let product = plan.product {
                        HStack(spacing: 5) {
                            Text(verbatim: commerce.price(product))
                                .environment(\.layoutDirection, .leftToRight)
                                .monospacedDigit()
                                .layoutPriority(1)
                            Text(verbatim: "·").accessibilityHidden(true)
                            LocalizedText("Billed every %@", commerce.period(product, locale: locale))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.stage(.footnote, weight: .medium))
                        .foregroundStyle(TrickoStyle.paper.opacity(0.85))
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 51)
                .foregroundStyle(TrickoStyle.accent)
                .trickoGlass(in: Capsule(), tint: TrickoStyle.accent.opacity(0.24))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle(disabledOpacity: purchaseActivityTitle != nil ? 0.92 : 0.55))
            .disabled(interactionLocked || selectedPlan == nil)
            .accessibilityIdentifier("membership.subscribe")
            .pageHorizontalMargins()
            .padding(.vertical, 10)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background { TrickoStyle.surface.ignoresSafeArea(.container, edges: .bottom) }
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        guard plan.product != nil else {
            purchaseAction = nil
            priceRequest += 1
            return
        }
        purchaseAction = .subscribe
        purchaseTask = Task {
            await commerce.purchase(planID: plan.id)
            purchaseTask = nil
        }
    }

    private var restoreLink: some View {
        Button {
            purchaseAction = .restore
            commerce.restore()
        } label: {
            HStack(spacing: 8) {
                if restoring { StageActivityMark(size: 16) }
                LocalizedText(restoring ? "Restoring purchases…" : "Restore purchases")
                    .font(.stage(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .foregroundStyle(TrickoStyle.accent)
            .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle(disabledOpacity: restoring ? 0.92 : 0.55))
            .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    @State private var rewardKind: AllowanceKind?
    private var rewardKinds: [AllowanceKind] {
        AllowanceKind.allCases.filter { quota.canRequestReward(for: $0, premium: commerce.premium) }
    }
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    membershipCard
                    AccountSettingsSection()
                    if api.session != nil {
                        allowance
                    } else {
                        ConnectionPanel(showsPolicyLinks: false)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let session = api.session {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                LocalizedText("Guest account").font(.stage(.subheadline, weight: .semibold))
                                if commerce.rightsVerified { accountStatus }
                            }
                            LocalizedText("ID · %@", session.userId.value).font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LocalizedText("Version %@", api.configuration.version).font(.stage(.caption))
                    }
                    .foregroundStyle(TrickoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .trickoPage()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            .trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
        }
            .trickoImmersiveChrome()
            .fullScreenCover(isPresented: $paywall) { MembershipView() }
            .fullScreenCover(item: $rewardKind) { kind in AllowanceLimitPrompt(kind: kind) }
            .onAppear { quota.resetIfNeeded() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
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
        let columns = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText("Today").font(.stage(.headline))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !commerce.premium, rewardKinds.isEmpty {
                    Button { paywall = true } label: { LocalizedText("View options") }
                        .font(.stage(.footnote, weight: .semibold)).foregroundStyle(TrickoStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel(Text(verbatim: L10n.text("View options for more views and downloads",
                                                                     language: AppLanguage.from(locale))))
                }
            }
            if let error = quota.error { ErrorNote(message: error) }
            if commerce.premium || quota.usage != nil {
                columns {
                    balance(.watch)
                    balance(.download)
                }
                if commerce.premium {
                    LocalizedText("Included with your membership").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                } else { AllowanceResetText() }
            } else if quota.error == nil {
                StageLoadingIndicator(title: "Checking your limits…", compact: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background { StageSurface(tone: .smoke) }
    }

    private func balance(_ kind: AllowanceKind) -> some View {
        let value = commerce.premium || quota.isUnlimited(kind) ? "Unlimited" : quota.remaining(kind).formatted(.number.locale(locale))
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(kind == .watch ? "Views left" : "Downloads left")
                    .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                LocalizedText(value).font(value == "Unlimited" ? .headline : .title.weight(.semibold))
                    .monospacedDigit().foregroundStyle(TrickoStyle.paper)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if rewardKinds.contains(kind) {
                Button { rewardKind = kind } label: {
                    LocalizedText(kind == .watch ? "Get more views" : "Get more downloads")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
                .font(.stage(.footnote, weight: .semibold)).foregroundStyle(TrickoStyle.accent)
                .buttonStyle(PressStyle()).disabled(unavailable)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LuckyRewardView: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LocalizedText("A little luck, on us").font(.stage(.headline)).foregroundStyle(TrickoStyle.paper)
                        .accessibilityAddTraits(.isHeader)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Keep exploring", action: dismiss)
                }.padding(20).frame(maxWidth: 360)
                    .trickoGlass(in: .rect(cornerRadius: 28), fallback: TrickoStyle.surface, interactive: false)
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .trickoImmersiveChrome()
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
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
