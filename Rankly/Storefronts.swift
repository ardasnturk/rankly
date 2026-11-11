import Foundation

struct Storefront: Identifiable, Hashable {
    let code: String         // ISO 3166 alpha-2, lowercase
    let id: Int              // App Store storefront id
    let languages: [String]  // main search languages, Apple's ISO 639-1 upper-case codes (as in languageCodesISO2A)
    var name: String { Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased() }
    var flag: String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init).joined()
    }
}

enum Storefronts {
    static let all: [Storefront] = [
        ("us", 143441, ["EN"]), ("tr", 143480, ["TR"]), ("gb", 143444, ["EN"]), ("de", 143443, ["DE"]),
        ("fr", 143442, ["FR"]), ("it", 143450, ["IT"]), ("es", 143454, ["ES"]), ("nl", 143452, ["NL"]),
        ("se", 143456, ["SV"]), ("no", 143457, ["NB", "NO"]), ("dk", 143458, ["DA"]), ("fi", 143447, ["FI"]),
        ("pl", 143478, ["PL"]), ("pt", 143453, ["PT"]), ("ch", 143459, ["DE", "FR", "IT"]), ("at", 143445, ["DE"]),
        ("be", 143446, ["NL", "FR"]), ("ie", 143449, ["EN"]), ("cz", 143489, ["CS"]), ("gr", 143448, ["EL"]),
        ("hu", 143482, ["HU"]), ("ro", 143487, ["RO"]), ("ua", 143492, ["UK"]), ("ru", 143469, ["RU"]),
        ("ca", 143455, ["EN", "FR"]), ("mx", 143468, ["ES"]), ("br", 143503, ["PT"]), ("ar", 143505, ["ES"]),
        ("cl", 143483, ["ES"]), ("co", 143501, ["ES"]), ("au", 143460, ["EN"]), ("nz", 143461, ["EN"]),
        ("jp", 143462, ["JA"]), ("kr", 143466, ["KO"]), ("cn", 143465, ["ZH"]), ("tw", 143470, ["ZH"]),
        ("hk", 143463, ["ZH", "EN"]), ("sg", 143464, ["EN", "ZH"]), ("my", 143473, ["MS", "EN"]),
        ("th", 143475, ["TH"]), ("id", 143476, ["ID"]), ("ph", 143474, ["EN"]), ("vn", 143471, ["VI"]),
        ("in", 143467, ["EN", "HI"]), ("pk", 143477, ["EN"]), ("sa", 143479, ["AR", "EN"]),
        ("ae", 143481, ["AR", "EN"]), ("il", 143491, ["HE", "EN"]), ("eg", 143516, ["AR"]),
        ("za", 143472, ["EN"]), ("ng", 143561, ["EN"]), ("kz", 143517, ["RU", "KK"]), ("az", 143568, ["AZ"]),
    ].map { Storefront(code: $0.0, id: $0.1, languages: $0.2) }

    static func byCode(_ code: String) -> Storefront {
        all.first { $0.code == code } ?? all[0]
    }

    /// Storefronts whose search language the app is localized in.
    static func matching(appLanguages: [String]) -> [Storefront] {
        let langs = Set(appLanguages.map { $0.uppercased() })
        return all.filter { !$0.languages.filter(langs.contains).isEmpty }
    }
}
