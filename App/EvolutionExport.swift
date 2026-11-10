import SwiftUI
import UniformTypeIdentifiers

struct EvolutionExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
    static func csv(groups: [EvolutionGroup], language: String, dimension: String, mode: String) -> String {
        let header = [ui("語言"), ui("中古分組維度"), ui("今音觀察維度"), ui("中古"), ui("今音"), ui("例字"), ui("發音"), ui("音韻地位"), ui("完整音韻地位")]
        let rows = groups.map { [language, dimension, mode, $0.oldValue, $0.modernValue,
                                $0.chars.joined(separator: " "), $0.readings.joined(separator: "\n"),
                                $0.positions.joined(separator: "\n"), $0.subtypes.joined(separator: "\n")] }
        // BOM lets Excel recognize UTF-8; quoting preserves commas, quotes and multiline IPA.
        return "\u{FEFF}" + ([header] + rows).map { row in
            row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}
