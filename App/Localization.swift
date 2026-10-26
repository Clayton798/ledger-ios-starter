import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans", english = "en", french = "fr"
    var id: String { rawValue }
    var title: String {
        switch self { case .chinese: return "中文"; case .english: return "English"; case .french: return "Français" }
    }
}
enum L10n {
    static var language: String { UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans" }
    static var bundle: Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
    static func text(_ value: String) -> String { bundle.localizedString(forKey: value, value: value, table: nil) }
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language), arguments: args)
    }
    static func cents(_ input: String) -> Int? { Money.inputCents(input, decimalComma: language == "fr") }
    static func merchant(_ value: String) -> String { MerchantDisplay.name(value) }
    static func period(_ key: String, startDay: Int) -> String {
        let label = LedgerDate.cycleLabel(key, startDay: startDay)
        return language == "zh-Hans" ? label : label.replacingOccurrences(of: " 至 ", with: " – ")
    }
}
