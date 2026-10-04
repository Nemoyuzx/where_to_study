import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case spanish = "es"
    case portuguese = "pt"
    case arabic = "ar"
    case russian = "ru"
    case turkish = "tr"
    case thai = "th"
    case malay = "ms"
    case vietnamese = "vi"
    case indonesian = "id"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .arabic: "العربية"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        case .thai: "ไทย"
        case .malay: "Bahasa Melayu"
        case .vietnamese: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    var nativeName: String { titleKey }
    var isRightToLeft: Bool { resolvedResourceName == "ar" }
    var usesChineseDateFormatting: Bool { resolvedResourceName.hasPrefix("zh") }

    var locale: Locale {
        if self != .system { return Locale(identifier: rawValue) }
        if let tag = Locale.preferredLanguages.first(where: { Self.resourceName(for: $0) != nil }) {
            return Locale(identifier: tag)
        }
        return Locale(identifier: "en")
    }

    var resolvedResourceName: String {
        resourceName(preferredLanguages: Locale.preferredLanguages)
    }

    func resourceName(preferredLanguages: [String]) -> String {
        if self != .system { return rawValue }
        return preferredLanguages.lazy.compactMap(Self.resourceName(for:)).first ?? "en"
    }

    static func resourceName(for tag: String) -> String? {
        let parts = tag.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        guard let language = parts.first else { return nil }
        if language == "zh" {
            if parts.contains("hans") { return "zh-Hans" }
            if parts.contains("hant") || parts.contains("cht") || parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        return allCases.first(where: { $0 != .system && $0.rawValue == language })?.rawValue
    }

    func dateFormat(chinese: String, english: String) -> String {
        if chinese == english { return english }
        if usesChineseDateFormatting { return chinese }
        if resolvedResourceName == "en" { return english }
        return DateFormatter.dateFormat(fromTemplate: english, options: 0, locale: locale) ?? english
    }
}

enum AppLocalization {
    static let defaultsKey = "appLanguage"

    private static let weekdaySymbols: [String: [String]] = {
        var values = [String: [String]]()
        for language in AppLanguage.allCases where language != .system {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = language.locale
            let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
            if symbols.count == 7 { values[language.rawValue] = Array(symbols.dropFirst()) + [symbols[0]] }
        }
        return values
    }()

    static func weekdaySymbol(for key: String, language: AppLanguage, prefixed: Bool = false) -> String {
        guard let index = ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: key) else { return string(key, language: language) }
        if language.usesChineseDateFormatting { return (prefixed ? string("周", language: language) : "") + key }
        return weekdaySymbols[language.resolvedResourceName]?[index] ?? key
    }

    private static let localizedBundles: [String: Bundle] = {
        var bundles = [String: Bundle]()
        for name in AppLanguage.allCases.filter({ $0 != .system }).map(\.rawValue) {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundles[name] = bundle
            }
        }
        return bundles
    }()

    static func persistedLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue)
        else { return .system }
        return language
    }

    static func string(_ key: String, language: AppLanguage, englishFallback: String? = nil) -> String {
        if language.resolvedResourceName == "en", let englishFallback { return englishFallback }
        let marker = "__wts_missing_localization__"
        if let bundle = localizedBundles[language.resolvedResourceName] {
            let value = bundle.localizedString(forKey: key, value: marker, table: nil)
            if value != marker { return value }
        }
        if language.resolvedResourceName == "zh-Hans" { return key }
        if let bundle = localizedBundles["en"] {
            let value = bundle.localizedString(forKey: key, value: marker, table: nil)
            if value != marker { return value }
        }
        return englishFallback ?? key
    }

    static func format(_ key: String, language: AppLanguage, englishFallback: String? = nil, arguments: [CVarArg]) -> String {
        String(format: string(key, language: language, englishFallback: englishFallback), locale: language.locale, arguments: arguments)
    }
}
