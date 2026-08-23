import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    var resolvedResourceName: String {
        resourceName(preferredLanguages: Locale.preferredLanguages)
    }

    func resourceName(preferredLanguages: [String]) -> String {
        switch self {
        case .simplifiedChinese:
            "zh-Hans"
        case .english:
            "en"
        case .system:
            preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? "zh-Hans"
                : "en"
        }
    }
}

enum AppLocalization {
    static let defaultsKey = "appLanguage"

    static func persistedLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue)
        else { return .system }
        return language
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        guard
            let path = Bundle.main.path(
                forResource: language.resolvedResourceName,
                ofType: "lproj"
            ),
            let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
