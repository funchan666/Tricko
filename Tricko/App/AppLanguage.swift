import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko, ja, id, pt, ar, es
    static let preferenceKey = "tricko.language.selection"
    static let systemSelection = "system"
    static func systemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first else { return .en }
        return from(Locale(identifier: first))
    }
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? systemSelection) ?? systemLanguage()
    }
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .en: "English"
        case .ko: "한국어"
        case .ja: "日本語"
        case .id: "Bahasa Indonesia"
        case .pt: "Português"
        case .ar: "العربية"
        case .es: "Español"
        }
    }
    static func from(_ locale: Locale) -> AppLanguage {
        AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .en
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var direction: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }
}

enum L10n {
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language -> (AppLanguage, Bundle)? in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        })

    static func text(_ key: String, language: AppLanguage = .current) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }


    private static let messagePatterns: [(String, NSRegularExpression)] = [
        "Error: %@",
        "Downloading · %@%",
        "%@ downloads left today",
        "Access through %@.",
        "Continue with %@",
        "%@, %@ per %@",
        "per %@",
        "%@ views · %@ saves left today",
        "Version %@",
        "ID · %@",
        "%@ videos",
        "%@ views left today",
        "%@ item · On this device",
        "%@ items · On this device",
        "Exporting · %@%",
        "Final duration · %@",
        "Rotate 90° · %@°",
        "No ad is available right now. %@",
        "Purchase service is unavailable (%@).",
        "The service is unavailable (%@). Please try again.",
        "Purchase is pending confirmation. %@",
        "The ad finished, but its reward could not be saved. %@",
        "An ad could not be loaded. Please try again later. %@",
        "Viewing is already unlimited until 5 AM. Watch a full ad for %@ more saves.",
        "Watch a full ad for unlimited viewing until 5 AM and %@ more saves.",
        "Watch a full ad for %@ more views and %@ more saves.",
        "%@ more views and %@ more saves have been added. Your ad progress stays the same.",
        "%@ more saves have been added. Your unlimited viewing stays active.",
        "Preview could not play. %@",
        "The export finished but could not be added to your library. %@",

    ].compactMap { key -> (String, NSRegularExpression)? in
        let pattern = "\\A" + key.components(separatedBy: "%@")
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(.+?)") + "\\z"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        return (key, expression)
    }

    static func display(_ value: String, language: AppLanguage = .current, depth: Int = 0) -> String {
        let exact = text(value, language: language)
        guard exact == value, depth < 3 else { return exact }
        let source = value as NSString
        for (key, expression) in messagePatterns {
            guard let match = expression.firstMatch(in: value, range: NSRange(location: 0, length: source.length)) else { continue }
            let arguments = (1..<match.numberOfRanges).map {
                display(source.substring(with: match.range(at: $0)), language: language, depth: depth + 1)
            }
            return format(key, arguments, language: language)
        }
        return value
    }

    static func format(_ key: String, _ arguments: [String], language: AppLanguage = .current) -> String {
        let template = text(key, language: language)
        let pattern = #"%(?:(\d+)\$)?@"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return template }
        let source = template as NSString
        var output = "", cursor = 0, nextArgument = 0
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let position = match.range(at: 1)
            let index = position.location == NSNotFound ? nextArgument : (Int(source.substring(with: position)) ?? 1) - 1
            output += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            nextArgument += 1
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }
}

struct LocalizedText: View {
    let key: String
    var arguments: [String] = []
    @Environment(\.locale) private var locale
    init(_ key: String, _ arguments: String...) { self.key = key; self.arguments = arguments }
    var body: some View {
        let language = AppLanguage.from(locale)
        Text(verbatim: arguments.isEmpty ? L10n.display(key, language: language) : L10n.format(key, arguments, language: language))
    }
}

struct LanguagePicker: View {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { languageCode = AppLanguage.systemSelection } label: {
                    HStack(spacing: 12) {
                        Glyph(symbol: .settings, size: 20, tint: TrickoStyle.coolAccent)
                        LocalizedText("Follow system")
                            .font(.stage(.body, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        selectionMark(selected: languageCode == AppLanguage.systemSelection)
                    }
                    .padding(16)
                    .trickoGlass(in: .rect(cornerRadius: 18))
                    .contentShape(.rect(cornerRadius: 18))
                }
                .accessibilityAddTraits(languageCode == AppLanguage.systemSelection ? .isSelected : [])
                .accessibilityIdentifier("language.system")

                let columns = typeSize.isAccessibilitySize
                    ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 146), spacing: 12)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        languageButton(language)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .trickoPage()
        }
        .foregroundStyle(TrickoStyle.paper).trickoScreenBackground()
        .navigationTitle("App language")
        .navigationBarTitleDisplayMode(.large)
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        let selected = languageCode == language.rawValue
        let translatedName = locale.localizedString(forLanguageCode: language.rawValue)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { languageCode = language.rawValue } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: language.nativeName)
                        .font(.stage(.headline)).layoutPriority(1)
                        .environment(\.layoutDirection, language.direction)
                    Spacer(minLength: 0)
                    selectionMark(selected: selected)
                }
                if let translatedName, translatedName.localizedCaseInsensitiveCompare(language.nativeName) != .orderedSame {
                    Text(verbatim: translatedName)
                        .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(selected ? TrickoStyle.raised : TrickoStyle.surface, in: shape)
            .overlay { shape.strokeBorder(selected ? TrickoStyle.coolAccent : TrickoStyle.line) }
            .contentShape(shape)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("language.\(language.rawValue)")
    }

    private func selectionMark(selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.stage(.subheadline, weight: .semibold))
            .foregroundStyle(selected ? TrickoStyle.coolAccent : TrickoStyle.secondary)
            .accessibilityHidden(true)
    }
}


struct LocalizedDateText: View {
    let date: Date
    @Environment(\.locale) private var locale
    var body: some View {
        Text(verbatim: date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
    }
}
