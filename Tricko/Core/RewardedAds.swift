import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform
import UIKit
import OSLog

@MainActor
final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var busy = false
    @Published private(set) var isPresenting = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var isPresentingConsent = false
    @Published var error: String?
    @Published var message: String?
    @Published var luckyReward: LuckyRewardNotice?
    @Published private(set) var startupFinished = false
    private var startupStarted = false
    @Published private(set) var isPreparingAppOpen = false
    private var appOpenTask: Task<Void, Never>?
    private var appOpenPreloadTask: Task<Void, Error>?
    private var preloadUnitID: String?
    private var preloadRequestID: UUID?
    private var preparedAppOpen: AppOpenAd?
    private var preparedAppOpenDate: Date?
    private var preparedUnitID: String?
    private var presentedUnitID: String?
    private let appOpenLog = Logger(subsystem: TrickoConfiguration.logSubsystem, category: "AppOpen")
    private var appOpenStage = "idle"
    private var appOpenDeadline: Task<Void, Never>?
    private var appOpenAttempt: UUID?
    private var appOpenHistoryKey: String?
    private var returnedFromBackground = false
    private var consentTask: Task<Void, Never>?
    private var needsConsentForm = false
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var unavailableReward: (() -> Void)?
    private var rewardGranted = false
    private var rewardAttempt: UUID?
    @Published private(set) var completedReward: UUID?
    private var started = false

    private var canRequestAds: Bool {
        !needsConsentForm && !isPresentingConsent && ConsentInformation.shared.canRequestAds
    }

    func watch(commerce: CommerceStore, quota: QuotaStore, kind: AllowanceKind) async {
        guard !Task.isCancelled, !busy, !isPresenting, !isPreparingAppOpen else { return }
        quota.resetIfNeeded()
        guard quota.canRequestReward(for: kind, premium: commerce.premium) else { return }
        guard commerce.rightsVerified, let policy = commerce.policy, let owner = commerce.api.session?.userId.value else {
            error = "Rewarded ads are not available right now. No views have been deducted."; return
        }
        let attemptID = UUID()
        rewardAttempt = attemptID
        busy = true
        defer {
            if rewardAttempt == attemptID { busy = false; rewardAttempt = nil }
        }
        error = nil
        message = nil
        luckyReward = nil
        rewardGranted = false
        unavailableReward = nil
        let packagedAppID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        guard let placement = commerce.release?.googlePlacement(for: policy.rewardedAdType, packagedAppID: packagedAppID,
                                                                 testMode: commerce.api.configuration.adsTestMode) else {
            appOpenLog.error("Rewarded ad configuration missing, invalid or inconsistent with the packaged App ID")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            return
        }
        let unitID = placement.unitID
        var timeout: Task<Void, Never>?
        defer { timeout?.cancel() }
        do {
            try await prepareSDK()
            guard rewardAttempt == attemptID else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.rewardAttempt == attemptID, !self.isPresenting else { return }
                self.rewardAttempt = nil
                self.busy = false
                self.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            }
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            try Task.checkCancellation()
            guard rewardAttempt == attemptID, canRequestAds, UIApplication.shared.applicationState == .active else { return }
            try ad.canPresent(from: nil)
            guard commerce.api.session?.userId.value == owner, !commerce.premium else { throw TrickoError.unauthorized }
            rewarded = ad
            unavailableReward = { [weak self] in
                self?.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            }
            ad.fullScreenContentDelegate = self
            let rewardID = UUID()
            isPresenting = true
            ad.present(from: nil) { [weak self, weak ad] in
                guard let self, let ad, self.rewarded === ad, !self.rewardGranted else { return }
                do {
                    try quota.reward(rewardID, owner: owner, kind: kind)
                    self.rewardGranted = true
                    self.message = kind == .watch ? "Your viewing allowance has been updated." : "Your download allowance has been updated."
                } catch { self.error = "The ad finished, but its reward could not be saved. \(error.localizedDescription)" }
            }
        } catch {
            guard rewardAttempt == attemptID else { return }
            isPresenting = false
            let failure = error as NSError
            if Task.isCancelled || error is CancellationError ||
                (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) { return }
            appOpenLog.error("Rewarded ad unavailable; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
        }
    }
    func cancelRewardLoading() {
        guard !isPresenting else { return }
        rewardAttempt = nil
        busy = false
    }

    private func grantUnavailableReward(_ attempt: UUID, owner: String, commerce: CommerceStore,
                                        quota: QuotaStore, kind: AllowanceKind) {
        do {
            guard commerce.api.session?.userId.value == owner else { throw TrickoError.unauthorized }
            guard !commerce.premium else { return }
            if let gift = try quota.rewardNoFill(attempt, owner: owner, kind: kind) {
                error = nil
                message = nil
                luckyReward = LuckyRewardNotice(message: gift)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func updateConsentAtLaunch() {
        consentTask = Task { [weak self] in
            guard let self else { return }
            let updateError = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) {
                    continuation.resume(returning: $0)
                }
            }
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            if let updateError {
                let failure = updateError as NSError
                appOpenLog.info("Consent update failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                return
            }
            needsConsentForm = true
            await presentPendingConsent()
        }
    }

    private func presentPendingConsent() async {
        guard needsConsentForm, !isPresentingConsent, UIApplication.shared.applicationState == .active else { return }
        needsConsentForm = false
        isPresentingConsent = true
        defer {
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            isPresentingConsent = false
        }
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            needsConsentForm = !ConsentInformation.shared.canRequestAds
            let failure = error as NSError
            appOpenLog.info("Consent form failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
        }
    }

    private func prepareSDK() async throws {
        try Task.checkCancellation()
        await consentTask?.value
        try Task.checkCancellation()
        guard canRequestAds else { throw TrickoError.service("Ads are unavailable with your current privacy choices.") }
        startSDKIfNeeded()
    }

    private func startSDKIfNeeded() {
        guard !started else { return }
        started = true
        MobileAds.shared.start { [weak self] _ in
            self?.appOpenLog.info("Google Mobile Ads initialization callback received")
        }
    }

    private func preloadAppOpen(unitID: String) async throws {
        try await prepareSDK()
        if preparedUnitID == unitID, preparedAppOpen != nil, let date = preparedAppOpenDate,
           Date().timeIntervalSince(date) >= 0, Date().timeIntervalSince(date) < 4 * 60 * 60 {
            appOpenLog.info("Using preloaded app-open ad")
            return
        }
        if let task = appOpenPreloadTask, preloadUnitID == unitID {
            try await task.value
            return
        }
        clearPreparedAppOpen()
        preloadUnitID = unitID
        let requestID = UUID()
        preloadRequestID = requestID
        let task = Task<Void, Error> { @MainActor [weak self] in
            let began = ContinuousClock.now
            do {
                try Task.checkCancellation()
                guard self?.canRequestAds == true else { throw CancellationError() }
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                try Task.checkCancellation()
                guard let self, self.preloadRequestID == requestID else { throw CancellationError() }
                self.preparedAppOpen = ad
                self.preparedAppOpenDate = Date()
                self.preparedUnitID = unitID
                self.appOpenPreloadTask = nil
                self.preloadUnitID = nil
                self.preloadRequestID = nil
                self.appOpenLog.info("App-open inventory ready after \(began.duration(to: .now).description, privacy: .public)")
            } catch {
                if let self, self.preloadRequestID == requestID {
                    self.appOpenPreloadTask = nil
                    self.preloadUnitID = nil
                    self.preloadRequestID = nil
                    let failure = error as NSError
                    self.appOpenLog.error("App-open inventory failed; domain=\(failure.domain, privacy: .public), code=\(failure.code), message=\(failure.localizedDescription, privacy: .public)")
                }
                throw error
            }
        }
        appOpenPreloadTask = task
        try await task.value
    }

    private func clearPreparedAppOpen() {
        appOpenPreloadTask?.cancel()
        appOpenPreloadTask = nil
        preloadUnitID = nil
        preloadRequestID = nil
        preparedAppOpen = nil
        preparedAppOpenDate = nil
        preparedUnitID = nil
    }

    func beginStartup(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard !startupStarted else { return }
        startupStarted = true
        updateConsentAtLaunch()
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: true)
    }

    func didEnterBackground() {
        returnedFromBackground = startupFinished && !isPresenting && !busy && !isPresentingConsent
        if isPreparingAppOpen { finishAppOpen(reason: "background", preservePreparation: true) }
    }

    func didBecomeActive(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        if needsConsentForm {
            consentTask = Task { [weak self] in
                guard let self else { return }
                await self.presentPendingConsent()
            }
        }
        guard returnedFromBackground else { return }
        returnedFromBackground = false
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: false)
    }

    private func requestAppOpen(commerce: CommerceStore, accountAccess: AccountAccessFlow, coldStart: Bool) {
        guard appOpenAttempt == nil, !busy, !isPresenting, !isPresentingConsent,
              !commerce.busy, !commerce.preparingPurchase, !accountAccess.isBusy else {
            if coldStart { startupFinished = true }
            return
        }
        let attempt = UUID()
        appOpenAttempt = attempt
        isPreparingAppOpen = true
        let testMode = commerce.api.configuration.adsTestMode
        let waitingBudget: Double
        if coldStart { waitingBudget = testMode ? 5 : 2 }
        else { waitingBudget = 1 }
        appOpenStage = "authentication"
        appOpenLog.info("App-open opportunity started; coldStart=\(coldStart), budget=\(waitingBudget)")
        scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget)
        appOpenTask = Task { [weak self] in
            guard let self else { return }
            let packagedAppID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
            let demoPlacement = testMode ? GoogleDemoInventory.placement(for: 1, packagedAppID: packagedAppID) : nil
            if let demoPlacement {
                Task { try? await self.preloadAppOpen(unitID: demoPlacement.unitID) }
            }
            do {
                try await commerce.api.prepareVisitor()
                try Task.checkCancellation()
                guard let owner = commerce.api.session?.userId.value else {
                    self.finishAppOpen(attempt: attempt); return
                }
                if self.appOpenAttempt == attempt {
                    self.appOpenStage = demoPlacement == nil ? "rights-and-configuration" : "rights"
                }
                self.appOpenLog.info("App-open guest authentication ready")
                await commerce.refresh(waitForConfiguration: demoPlacement == nil)
                try Task.checkCancellation()
                guard commerce.api.session?.userId.value == owner,
                      commerce.rightsVerified, !commerce.premium else {
                    self.finishAppOpen(attempt: attempt, reason: commerce.premium ? "membership" : "rights-unavailable"); return
                }
                let placement = testMode ? demoPlacement : commerce.release?.googlePlacement(
                    for: 1, packagedAppID: packagedAppID, testMode: false)
                guard let placement else {
                    self.appOpenLog.error("App-open configuration missing, invalid or inconsistent with the packaged App ID")
                    self.finishAppOpen(attempt: attempt, reason: "ad-configuration-unavailable"); return
                }
                let serverInterval = commerce.release?.adList?.first {
                    $0.adType == 1 && $0.advertiser?.lowercased() == "google"
                }?.displayInterval
                let interval = placement.isOfficialDemo ? 0 : serverInterval
                let unitID = placement.unitID
                let key = "tricko.app-open.last-impression.\(commerce.api.configuration.bundleID).\(commerce.api.configuration.apiBaseURL?.host ?? "none").\(placement.isOfficialDemo ? "demo" : "production")"
                self.appOpenLog.info("App-open rights/configuration ready; intervalMinutes=\(interval ?? -1)")
                if self.appOpenAttempt == attempt { self.appOpenStage = "ad-preparation" }
                guard AppOpenTiming.isDue(intervalMinutes: interval,
                    lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    Task { try? await self.preloadAppOpen(unitID: unitID) }
                    self.finishAppOpen(attempt: attempt, reason: "interval-not-due")
                    return
                }
                try await self.preloadAppOpen(unitID: unitID)
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      commerce.rightsVerified, !commerce.premium, self.canRequestAds,
                      UIApplication.shared.applicationState == .active,
                      !self.busy, !self.isPresenting, !commerce.busy, !commerce.preparingPurchase,
                      !accountAccess.isBusy,
                      AppOpenTiming.isDue(intervalMinutes: interval,
                        lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    self.finishAppOpen(attempt: attempt, reason: "presentation-no-longer-eligible"); return
                }
                guard self.preparedUnitID == unitID, let ad = self.preparedAppOpen else {
                    self.finishAppOpen(attempt: attempt, reason: "inventory-unavailable")
                    return
                }
                do { try ad.canPresent(from: nil) }
                catch {
                    self.preparedAppOpen = nil
                    self.preparedAppOpenDate = nil
                    self.preparedUnitID = nil
                    throw error
                }
                self.preparedAppOpen = nil
                self.preparedAppOpenDate = nil
                self.preparedUnitID = nil
                self.presentedUnitID = unitID
                self.appOpenStage = "presenting"
                self.appOpenLog.info("App-open ad ready; presenting")
                self.appOpenAd = ad
                self.appOpenHistoryKey = key
                ad.fullScreenContentDelegate = self
                self.appOpenDeadline?.cancel()
                self.isPreparingAppOpen = false
                self.isPresenting = true
                ad.present(from: nil)
            } catch {
                if self.appOpenAttempt == attempt {
                    let failure = error as NSError
                    self.appOpenLog.info("App-open preparation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                }
                self.finishAppOpen(attempt: attempt, reason: "preparation-failed")
            }
        }
    }

    private func scheduleAppOpenDeadline(attempt: UUID, seconds: Double) {
        appOpenDeadline?.cancel()
        appOpenDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.appOpenAttempt == attempt, !self.isPresenting else { return }
            self.finishAppOpen(attempt: attempt, reason: "deadline", preservePreparation: true)
        }
    }

    private func finishAppOpen(attempt: UUID? = nil, reason: String = "finished", preservePreparation: Bool = false) {
        if let attempt, attempt != appOpenAttempt { return }
        appOpenLog.info("App-open ended; reason=\(reason, privacy: .public), stage=\(self.appOpenStage, privacy: .public)")
        appOpenStage = "idle"
        appOpenAttempt = nil
        appOpenDeadline?.cancel()
        appOpenDeadline = nil
        if !preservePreparation { appOpenTask?.cancel() }
        appOpenTask = nil
        appOpenAd = nil
        appOpenHistoryKey = nil
        isPreparingAppOpen = false
        isPresenting = false
        startupFinished = true
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        guard let current = appOpenAd, ad === current, let key = appOpenHistoryKey else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        appOpenLog.info("App-open impression recorded")
    }

    func privacyOptions() async {
        guard privacyOptionsRequired, !isPresentingConsent, !isPreparingAppOpen, !isPresenting, !busy else { return }
        error = nil
        clearPreparedAppOpen()
        isPresentingConsent = true
        defer {
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            isPresentingConsent = false
        }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            if ConsentInformation.shared.canRequestAds { needsConsentForm = false }
        } catch { self.error = error.localizedDescription }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if let current = appOpenAd, ad === current {
            let unitID = presentedUnitID
            presentedUnitID = nil
            finishAppOpen()
            if let unitID { Task { try? await self.preloadAppOpen(unitID: unitID) } }
            return
        }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        unavailableReward = nil
        isPresenting = false
        if rewardGranted { completedReward = UUID() }
        else if error == nil { message = "No reward was received. Finish the ad to receive your reward." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let current = appOpenAd, ad === current {
            let failure = error as NSError
            appOpenLog.error("App-open presentation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            let unitID = presentedUnitID
            presentedUnitID = nil
            finishAppOpen(reason: "presentation-failed")
            if let unitID { Task { try? await self.preloadAppOpen(unitID: unitID) } }
            return
        }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        isPresenting = false
        let fallback = unavailableReward
        unavailableReward = nil
        if !rewardGranted { fallback?() }
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
