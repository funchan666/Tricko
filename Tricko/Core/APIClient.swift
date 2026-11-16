import Foundation
import Combine
import Security
import UIKit
import OSLog

struct TrickoConfiguration {
    static let logSubsystem = Bundle.main.bundleIdentifier ?? "Tricko"
    static let servicePackageName = "com.trickostudio.videodesk"
    let apiBaseURL: URL?
    let bundleID: String
    let releaseName: String
    let version: String
    let websiteURL: URL?
    let privacyURL: URL?
    let termsURL: URL?
    let adsTestMode: Bool
    static var current: Self {
        let bundle = Bundle.main
        func value(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rawHost = value("TrickoAPIHost")
        let host = rawHost.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = host.isEmpty || host.contains("$(") || host.contains("/") ? nil : URL(string: "https://" + host)
        let releaseName = value("TrickoReleaseName")
        return Self(apiBaseURL: base, bundleID: bundle.bundleIdentifier ?? "",
                    releaseName: releaseName.isEmpty || releaseName.contains("$(") ? "Tricko" : releaseName,
                    version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
                    websiteURL: WebAddress.media(value("TrickoWebsiteURL")),
                    privacyURL: WebAddress.media(value("TrickoPrivacyURL")),
                    termsURL: WebAddress.media(value("TrickoTermsURL")),
                    adsTestMode: value("TrickoAdsTestMode") == "YES")
    }
    var isReady: Bool {
        apiBaseURL?.host != nil && !bundleID.isEmpty && !bundleID.contains("unconfigured")
            && !bundleID.contains("$(")
    }
}


enum SecureStorage {
    private static let service = "Tricko.Session"
    static func read(_ key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TrickoError.storage }
        return data
    }
    static func write(_ data: Data, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw TrickoError.storage }
        } else if status != errSecSuccess { throw TrickoError.storage }
        guard try read(key) == data else { throw TrickoError.storage }
    }
    static func remove(_ key: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TrickoError.storage }
    }
}

enum InstallationIdentity {
    static func prepare() throws {
        let files = FileManager.default
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try files.createDirectory(at: support, withIntermediateDirectories: true)
        var marker = support.appendingPathComponent("TrickoInstallation")
        let existing = try? String(contentsOf: marker, encoding: .utf8)
        if existing == "ready" { return }
        let legacyLibrary = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrickoMedia", isDirectory: true)
        if existing == "reset" || !files.fileExists(atPath: legacyLibrary.path) {
            try Data("reset".utf8).write(to: marker, options: .atomic)
            try SecureStorage.remove("visitor")
            try SecureStorage.remove("installation")
        }
        try Data("ready".utf8).write(to: marker, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try marker.setResourceValues(values)
    }
}

@MainActor
final class APIClient: ObservableObject {
    private let diagnostics = Logger(subsystem: TrickoConfiguration.logSubsystem, category: "API")
    @Published private(set) var session: VisitorSession?
    @Published private(set) var offlineOwnerID: String?
    let configuration: TrickoConfiguration
    private let transport: URLSession
    private var loginTask: Task<VisitorSession, Error>?
    private var sessionGeneration = UUID()
    private var storageFailure: Error?

    init(configuration: TrickoConfiguration = .current) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        transport = URLSession(configuration: config)
        do {
            try InstallationIdentity.prepare()
            if let installation = try SecureStorage.read("installation"), !installation.isEmpty,
               let data = try SecureStorage.read("visitor"),
               let visitor = try? JSONDecoder().decode(VisitorSession.self, from: data) {
                offlineOwnerID = visitor.userId.value.nilIfBlank
            }
        } catch {
            session = nil
            storageFailure = error
        }
    }

    func prepareVisitor() async throws {
        guard session == nil else { return }
        _ = try await signIn()
    }

    @discardableResult func signIn() async throws -> VisitorSession {
        guard configuration.isReady else { throw TrickoError.configuration }
        if let storageFailure { throw storageFailure }
        if let loginTask { return try await loginTask.value }
        let generation = sessionGeneration
        let task = Task<VisitorSession, Error> { [self] in
            let device: String
            if let stored = try SecureStorage.read("installation"), let saved = String(data: stored, encoding: .utf8), !saved.isEmpty {
                device = saved
            } else {
                device = UUID().uuidString
                try SecureStorage.write(Data(device.utf8), key: "installation")
            }
            let publicIPv4 = try await loginPublicIPv4()
            try Task.checkCancellation()
            let body = try JSONSerialization.data(withJSONObject: [
                "deviceCode": device, "source": TrickoConfiguration.servicePackageName, "uniqueId": publicIPv4
            ])
            diagnostics.debug("Guest login payload: uniqueId IPv4 present \(!publicIPv4.isEmpty)")
            let result: VisitorSession = try await perform("/app-api/member/auth/app_tourist_login", method: "POST", body: body, authenticated: false)
            guard !result.accessToken.isEmpty, !result.userId.value.isEmpty else { throw TrickoError.invalidResponse }
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            try SecureStorage.write(JSONEncoder().encode(result), key: "visitor")
            session = result
            offlineOwnerID = result.userId.value
            return result
        }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func loginPublicIPv4() async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let lookup = URLSession(configuration: config)
        defer { lookup.invalidateAndCancel() }
        return try await withThrowingTaskGroup(of: String.self) { group in
            for address in ["https://ipv4.icanhazip.com", "https://api.ipify.org/"] {
                group.addTask { try await Self.readPublicIPv4(address, using: lookup) }
            }
            for try await candidate in group where !candidate.isEmpty {
                group.cancelAll()
                return candidate
            }
            try Task.checkCancellation()
            return ""
        }
    }

    private nonisolated static func readPublicIPv4(_ address: String, using lookup: URLSession) async throws -> String {
        guard let url = URL(string: address) else { return "" }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await lookup.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 64, let text = String(data: data, encoding: .utf8) else { return "" }
            let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let octets = candidate.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ octet in
                !octet.isEmpty && octet.utf8.allSatisfy { (48...57).contains($0) } && UInt8(octet) != nil
            }) else { return "" }
            return candidate
        } catch {
            try Task.checkCancellation()
            return ""
        }
    }

    func releaseConfiguration() async throws -> ReleaseConfiguration {
        guard let session else { throw TrickoError.unauthorized }
        return try await perform("/app-api/flow/release-package/getV2", query: [
            "platform": "IOS", "name": configuration.releaseName, "version": configuration.version,
            "lang": AppLanguage.current.rawValue, "userId": session.userId.value,
            "time": TimeZone.current.identifier, "input": UITextInputMode.activeInputModes.compactMap(\.primaryLanguage).joined(separator: ",")
        ], authenticated: false)
    }
    func channels(links: [String]) async throws -> [LandingInfo] {
        let codes = links.compactMap { WebAddress.landingCode($0) }
        guard !codes.isEmpty else { return [] }
        let body = try JSONSerialization.data(withJSONObject: codes.map {
            ["externalLinks": $0, "packageName": TrickoConfiguration.servicePackageName]
        })
        return try await perform("/app-api/flow/land-page/info_by_links_list", method: "POST", body: body, authenticated: false)
    }
    func resolve(_ link: String, password: String) async throws -> LandingInfo {
        try await perform("/app-api/flow/land-page/info_by_links", query: [
            "externalLinks": link, "password": password, "packageName": TrickoConfiguration.servicePackageName],
            missingDataMessage: "No content was returned for this link. Check the code, including uppercase and lowercase letters, or try again later.")
    }
    func channelPage(link: String, page: Int) async throws -> ChannelPage {
        try await perform("/app-api/flow/land-page/list_by_links_page", query: [
            "externalLinks": link, "pageNo": String(max(1, page)), "pageSize": "20",
            "packageName": TrickoConfiguration.servicePackageName])
    }
    func feed(query: String, feedID: String?, cursor: String?) async throws -> LessonFeedPage {
        guard let session else { throw TrickoError.unauthorized }
        var queryItems = ["userId": session.userId.value, "packageName": TrickoConfiguration.servicePackageName, "pageSize": "10"]
        if let feedID = feedID?.nilIfBlank { queryItems["feedId"] = feedID }
        if let cursor = cursor?.nilIfBlank { queryItems["cursor"] = cursor }
        if let query = query.nilIfBlank { queryItems["query"] = query }
        return try await perform("/app-api/flow/search-check", query: queryItems, emptyDataValue: LessonFeedPage.empty)
    }

    func rights() async throws -> UserRights {
        try await perform("/app-api/member/user/get")
    }
    func paymentRequest(path: String, body: [String: Any], owner: VisitorSession) async throws -> Data {
        guard configuration.isReady, let base = configuration.apiBaseURL else { throw TrickoError.configuration }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(owner.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw TrickoError.invalidResponse }
        if http.statusCode == 401 { throw TrickoError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw TrickoError.service("Purchase service is unavailable (\(http.statusCode)).") }
        struct Status: Decodable { let code: Int; let msg: String? }
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.code == 0 else { throw TrickoError.service(status.msg ?? "Purchase confirmation failed.") }
        return data
    }

    private func perform<Value: Decodable>(_ path: String, method: String = "GET", query: [String: String] = [:],
                                           body: Data? = nil, authenticated: Bool = true, retry: Bool = true,
                                           missingDataMessage: String? = nil, emptyDataValue: Value? = nil) async throws -> Value {
        guard configuration.isReady, let base = configuration.apiBaseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw TrickoError.configuration }
        var effectiveQuery = query
        if authenticated, effectiveQuery["userId"] != nil { effectiveQuery["userId"] = session?.userId.value }
        components.queryItems = effectiveQuery.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw TrickoError.configuration }
        #if DEBUG
        if path == "/app-api/flow/release-package/getV2" {
            diagnostics.debug("Release configuration name: \(effectiveQuery["name"] ?? "", privacy: .public)")
        } else if path == "/app-api/flow/search-check" {
            diagnostics.debug("Search request: query UTF-8 bytes \(effectiveQuery["query"]?.utf8.count ?? 0), paginated \(effectiveQuery["cursor"] != nil)")
        }
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let usedToken = session?.accessToken
        if authenticated {
            guard let usedToken else { throw TrickoError.unauthorized }
            request.setValue("Bearer \(usedToken)", forHTTPHeaderField: "Authorization")
        }
        let generation = sessionGeneration
        let (data, response) = try await send(request)
        try Task.checkCancellation()
        if authenticated, generation != sessionGeneration { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw TrickoError.invalidResponse }
        #if DEBUG
        diagnostics.debug("\(method, privacy: .public) \(path, privacy: .public) HTTP \(response.statusCode)")
        #endif
        if response.statusCode == 401, authenticated {
            guard retry else { throw TrickoError.unauthorized }
            if session?.accessToken == usedToken { try await signIn() }
            return try await perform(path, method: method, query: query, body: body, authenticated: true, retry: false,
                                     missingDataMessage: missingDataMessage, emptyDataValue: emptyDataValue)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TrickoError.service("The service is unavailable (\(response.statusCode)). Please try again.")
        }
        let result: APIEnvelope<Value>
        do { result = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data) }
        catch {
            #if DEBUG
            diagnostics.error("\(path, privacy: .public): response decoding failed")
            #endif
            throw TrickoError.invalidResponse
        }
        #if DEBUG
        diagnostics.debug("\(path, privacy: .public): business code \(result.code), data present \(result.data != nil)")
        #endif
        guard result.code == 0 else { throw TrickoError.service(result.msg?.nilIfBlank ?? "The request could not be completed.") }
        guard let value = result.data ?? emptyDataValue else {
            if let missingDataMessage { throw TrickoError.service(missingDataMessage) }
            throw TrickoError.invalidResponse
        }
        return value
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await transport.data(for: request) }
        catch {
            #if DEBUG
            let code = (error as NSError).code
            diagnostics.error("\(request.url?.path ?? "", privacy: .public): transport failed (\(code))")
            #endif
            throw TrickoError.connectionFailure(error)
        }
    }
}
