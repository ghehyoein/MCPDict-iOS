import SwiftUI

enum GyField: String, CaseIterable {
    case she = "攝", rhyme = "韻", initial = "聲母", openness = "開合", division = "等", subclass = "重紐", tone = "聲調"
}

struct GyGroup: Decodable, Identifiable {
    let number, title, fanqie, position, she, rhyme, initial, openness, division, subclass, tone: String
    let characters: [String]
    var id: [String] { [number, position, title, fanqie, she] }
    var label: String { [characters.first ?? "", fanqie, position].joined(separator: " · ") }
    func value(_ field: GyField) -> String {
        switch field {
        case .she: return she
        case .rhyme: return rhyme
        case .initial: return initial
        case .openness: return openness
        case .division: return division
        case .subclass: return subclass
        case .tone: return tone
        }
    }
}

struct GyIndex {
    let groups: [GyGroup]
    let sheOrder: [String]
    var byCharacter: [String: [Int]] = [:]

    init(groups: [GyGroup]) {
        self.groups = groups
        sheOrder = Self.ordered(groups.map(\.she))
        for (i, group) in groups.enumerated() {
            var keys = Set(group.characters)
            // The source also uses annotated headwords such as 淞〈凇〉 and ｛婔｝.
            for word in group.characters where word.contains("〈") || word.hasPrefix("｛") {
                keys.formUnion(word.components(separatedBy: CharacterSet(charactersIn: "〈〉｛｝")).filter { !$0.isEmpty })
            }
            for key in keys { byCharacter[key, default: []].append(i) }
        }
    }
    static func ordered(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0).inserted }
    }
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "guangyun-overview", withExtension: "json", subdirectory: "BundledTables") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Self(groups: JSONDecoder().decode([GyGroup].self, from: Data(contentsOf: url)))
    }
    func matching(_ reading: GyGroup, fields: Set<GyField>) -> [GyGroup] {
        groups.filter { group in fields.allSatisfy { group.value($0) == reading.value($0) } }
    }
    func readings(_ word: String) -> [Int] {
        if let exact = byCharacter[word] { return exact }
        guard word.count == 1 else { return [] }
        return Set(CharacterVariants.pickerChoices(word).flatMap { byCharacter[$0] ?? [] }).sorted()
    }
}

struct GuangyunOverview: View {
    @State private var index: GyIndex?
    @State private var error = ""
    @State private var she = ""
    @State private var input = ""
    @State private var submitted = ""
    @State private var readings = [Int]()
    @State private var selected = 0
    @State private var fields = Set(GyField.allCases)
    @FocusState private var focused: Bool

    var body: some View {
        List {
            if let index {
                HStack {
                    TextField(ui("輸入單字反查"), text: $input)
                        .focused($focused).autocorrectionDisabled().onSubmit { search(index) }
                    Button(ui("查詢")) { search(index) }.buttonStyle(.borderless)
                    if !submitted.isEmpty {
                        Button(ui("清除")) { input = ""; search(index) }.buttonStyle(.borderless)
                    }
                }
                if submitted.isEmpty { browse(index) } else { reverse(index) }
            } else if error.isEmpty { ProgressView() } else { Text(error) }
        }.appPageStyle().navigationTitle(ui("廣韻總覽"))
        .task {
            guard index == nil else { return }
            do {
                let loaded = try await Task.detached { try GyIndex.load() }.value
                she = loaded.sheOrder.first ?? ""; index = loaded
            } catch { self.error = error.localizedDescription }
        }
    }

    private func search(_ index: GyIndex) {
        focused = false
        submitted = input.trimmingCharacters(in: .whitespacesAndNewlines)
        readings = index.readings(submitted)
        selected = readings.first ?? 0
        fields = Set(GyField.allCases)
    }

    @ViewBuilder private func browse(_ index: GyIndex) -> some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(index.sheOrder, id: \.self) { name in
                    Button(name) { she = name }.buttonStyle(.bordered)
                        .tint(name == she ? AppAccent.color : .gray)
                }
            }
        }
        let groups = index.groups.filter { $0.she == she }
        let byRhyme = Dictionary(grouping: groups, by: \.rhyme)
        ForEach(GyIndex.ordered(groups.map(\.rhyme)), id: \.self) { rhyme in
            Section {
                headingRows(byRhyme[rhyme] ?? [])
            } header: { Text(ui("韻") + " · " + rhyme) }
        }
    }

    @ViewBuilder private func headingRows(_ groups: [GyGroup]) -> some View {
        let byHeading = Dictionary(grouping: groups, by: \.title)
        ForEach(GyIndex.ordered(groups.map(\.title)), id: \.self) { title in
            Text(title).font(.headline).foregroundStyle(AppAccent.color)
            ForEach(byHeading[title] ?? []) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.label).font(.subheadline.weight(.semibold))
                    Text(group.characters.joined(separator: " ")).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private func reverse(_ index: GyIndex) -> some View {
        if readings.isEmpty { Text(ui("廣韻未收此字")) }
        else {
            Picker(ui("音韻地位"), selection: $selected) {
                ForEach(readings, id: \.self) { i in Text(index.groups[i].label).tag(i) }
            }
            let reading = index.groups[selected]
            Section(ui("比對條件")) {
                ForEach(GyField.allCases, id: \.self) { field in
                    Toggle(isOn: Binding(get: { fields.contains(field) }, set: { enabled in
                        if enabled { fields.insert(field) } else { fields.remove(field) }
                    })) {
                        HStack { Text(ui(field.rawValue)); Spacer(); Text(reading.value(field).isEmpty ? "—" : reading.value(field)) }
                    }
                }
            }
            let matches = index.matching(reading, fields: fields)
            headingRows(matches)
        }
    }
}
