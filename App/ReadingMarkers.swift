import SwiftUI

enum ReadingMarkers {
    static let meanings: [(Character, String)] = [("-", "白讀"), ("=", "文讀"), ("?", "待考"), ("*", "俗字")]
    static let help = "-為白讀標記，=為文讀標記，?為待考標記，*為俗字標記"
    static func keys(_ pronunciation: String) -> [String] {
        let symbols = Set(meanings.map(\.0))
        var found = Set<Character>()
        for token in pronunciation.split(whereSeparator: { $0.isWhitespace }) {
            // Only trailing annotation markers count, never medial hyphens or reconstruction prefixes.
            let suffix = token.reversed().prefix { symbols.contains($0) }
            if suffix.count < token.count { found.formUnion(suffix) }
        }
        return meanings.filter { found.contains($0.0) }.map(\.1)
    }
    static func note(_ original: String, pronunciation: String) -> String {
        let labels = keys(pronunciation).map(ui)
        return ([original].filter { !$0.isEmpty } + labels).joined(separator: "；")
    }
}

extension Reading {
    var displayNote: String { ReadingMarkers.note(note, pronunciation: pronunciation) }
}

struct ReadingMarkerHelpButton: View {
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless).accessibilityLabel(ui("註釋"))
            .accessibilityIdentifier("readingMarkerHelp")
            .alert(ui("註釋"), isPresented: $showing) { Button(ui("好"), role: .cancel) {} }
                message: { Text(ui(ReadingMarkers.help)) }
    }
}
