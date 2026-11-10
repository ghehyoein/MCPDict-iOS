import SwiftUI

// Targets and ordering match Android ResultAdapter's online dictionary menu.
enum OnlineDictionary: String, CaseIterable, Identifiable {
    case zdic, zisea, moedict, zitools, ccamc, kangxi, unihan, chise
    var id: String { rawValue }
    var title: String {
        switch self {
        case .zdic: return "漢典"
        case .zisea: return "字海"
        case .moedict: return "萌典"
        case .zitools: return "字統網"
        case .ccamc: return "古今文字集成"
        case .kangxi: return "康熙字典"
        case .unihan: return "Unihan"
        case .chise: return "CHISE"
        }
    }
    func url(for character: String) -> URL? {
        guard !character.isEmpty, let scalar = character.unicodeScalars.first,
              let encoded = character.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        let hex = String(scalar.value, radix: 16, uppercase: true)
        switch self {
        case .zdic: return URL(string: "https://zdic.net/hans/" + encoded)
        case .zisea: return URL(string: "http://zisea.com/zscontent.asp?uni=" + hex)
        case .moedict: return URL(string: "https://www.moedict.tw/" + encoded)
        case .zitools: return URL(string: "https://zi.tools/zi/" + encoded)
        case .ccamc: return URL(string: "http://www.ccamc.co/cjkv.php?cjkv=" + encoded)
        case .kangxi: return URL(string: "https://kangxizidian.com/kxhans/" + encoded)
        case .unihan: return URL(string: "https://www.unicode.org/cgi-bin/GetUnihanData.pl?codepoint=" + encoded)
        case .chise: return URL(string: "https://www.chise.org/est/view/character/" + encoded)
        }
    }
}

struct OnlineDictionaryPreferences: Codable, Equatable {
    static let key = "onlineDictionaryPresentation"
    var order = OnlineDictionary.allCases.map(\.rawValue)
    var hidden = Set<String>()
    static func load(_ raw: String) -> Self {
        guard let data = raw.data(using: .utf8), var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        let allowed = OnlineDictionary.allCases.map(\.rawValue)
        var seen = Set<String>()
        value.order = (value.order + allowed).filter { allowed.contains($0) && seen.insert($0).inserted }
        value.hidden.formIntersection(allowed)
        return value
    }
    var visible: [OnlineDictionary] { order.filter { !hidden.contains($0) }.compactMap(OnlineDictionary.init(rawValue:)) }
    var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
}

struct OnlineDictionaryMenu: View {
    let character: String
    @AppStorage(OnlineDictionaryPreferences.key) private var raw = ""
    var body: some View {
        let dictionaries = OnlineDictionaryPreferences.load(raw).visible
        if !dictionaries.isEmpty {
            Menu {
                ForEach(dictionaries) { dictionary in
                    if let url = dictionary.url(for: character) {
                        Link(ui(dictionary.title), destination: url)
                            .accessibilityIdentifier("onlineDictionary-" + dictionary.rawValue)
                    }
                }
            } label: { Text("⋯").foregroundStyle(AppAccent.color) }
                .accessibilityLabel(ui("在線字典")).accessibilityIdentifier("onlineDictionaryMenu")
        }
    }
}

struct OnlineDictionarySettingsSection: View {
    @AppStorage(OnlineDictionaryPreferences.key) private var raw = ""
    private var settings: OnlineDictionaryPreferences {
        get { .load(raw) }
        nonmutating set { raw = newValue.encoded }
    }
    var body: some View {
        Section(ui("在線字典")) {
            ForEach(settings.order, id: \.self) { id in
                if let dictionary = OnlineDictionary(rawValue: id) {
                    Toggle(ui(dictionary.title), isOn: Binding(get: { !settings.hidden.contains(id) }, set: {
                        if $0 { settings.hidden.remove(id) } else { settings.hidden.insert(id) }
                    })).accessibilityIdentifier("onlineDictionaryToggle-" + id)
                }
            }.onMove { settings.order.move(fromOffsets: $0, toOffset: $1) }
        }
    }
}

struct AddCustomLanguageButton: View {
    let name: String
    @ObservedObject var state: LanguageSelectionState
    var body: some View {
        Button {
            if !state.custom.members.insert(name).inserted { state.custom.members.remove(name) }
        } label: {
            Text(ui(state.custom.members.contains(name) ? "將該語言移出自選語言" : "將該語言加入自選語言"))
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(StaticCustomLanguageButtonStyle()).accessibilityIdentifier("tableCustomLanguage")
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

struct StaticCustomLanguageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(12).foregroundStyle(AppAccent.color)
            .background(AppAccent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppAccent.color, lineWidth: 1))
    }
}
