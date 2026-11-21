import Foundation
import ZIPFoundation

// Android SchemeWorkbook.write exports one worksheet, with the scheme name in the filename.
enum AndroidSchemeWorkbook {
    static var invalid: DictionaryFailure { DictionaryFailure(message: ui("無效的自選分區檔案")) }

    static func read(_ url: URL) throws -> CustomSchemeArchive {
        let zip = try ZIPFoundation.Archive(url: url, accessMode: .read)
        var remaining = 64 * 1024 * 1024
        func parse(_ entry: Entry, strings: [String]) throws -> Cells {
            guard entry.uncompressedSize <= UInt64(remaining) else { throw invalid }
            var data = Data()
            _ = try zip.extract(entry) { chunk in
                guard chunk.count <= remaining else { throw invalid }
                data.append(chunk)
                remaining -= chunk.count
            }
            let cells = Cells(shared: strings)
            let parser = XMLParser(data: data)
            parser.delegate = cells
            guard parser.parse(), parser.parserError == nil else { throw invalid }
            return cells
        }
        var shared = [String]()
        if let entry = zip["xl/sharedStrings.xml"] { shared = try parse(entry, strings: []).strings }
        var table: [[Int: String]]?
        var columns = [Int]()
        for entry in zip where entry.path.hasPrefix("xl/worksheets/") && entry.path.hasSuffix(".xml") {
            let rows = try parse(entry, strings: shared).rows
            for (index, row) in rows.enumerated() {
                let headings = row.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let keys = [["語言", "语言"], ["自選分區", "自选分区"], ["自選顏色", "自选颜色"]].compactMap { aliases in
                    headings.first { aliases.contains($0.value) }?.key
                }
                guard keys.count == 3 else { continue }
                guard table == nil else { throw invalid }
                columns = keys
                table = Array(rows.dropFirst(index + 1))
                break
            }
        }
        guard let table else { throw invalid }
        let root = CustomLanguageSchemes.normalize(url.deletingPathExtension().lastPathComponent)
        var store = CustomLanguageSchemes()
        store.schemes = [.init(name: root, languages: [])]
        var indices = [root: 0]
        for row in table {
            let language = (row[columns[0]] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !language.isEmpty else { continue }
            var path = root
            for group in (row[columns[1]] ?? "").split(whereSeparator: { "-－／/".contains($0) }) {
                path += "－" + CustomLanguageSchemes.normalize(String(group))
                if indices[path] == nil {
                    indices[path] = store.schemes.count
                    store.schemes.append(.init(name: path, languages: []))
                }
            }
            let index = indices[path]!
            store.schemes[index].languages.insert(language)
            let color = (row[columns[2]] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !color.isEmpty {
                guard let hex = CustomLanguageSchemes.validColor(color) else { throw invalid }
                if store.schemes[index].languageColors == nil { store.schemes[index].languageColors = [:] }
                store.schemes[index].languageColors?[language] = hex
            }
        }
        guard store.schemes.contains(where: { !$0.languages.isEmpty }) else { throw invalid }
        for i in store.schemes.indices {
            guard let colors = store.schemes[i].languageColors, colors.count == store.schemes[i].languages.count,
                  let first = colors.values.first, colors.values.allSatisfy({ $0 == first }) else { continue }
            store.schemes[i].colorHex = first
            store.schemes[i].languageColors = nil
        }
        return CustomSchemeArchive(store)
    }

    private final class Cells: NSObject, XMLParserDelegate {
        let shared: [String]
        var strings = [String]()
        var rows = [[Int: String]]()
        private var row = [Int: String]()
        private var column = 0
        private var type = ""
        private var value = ""
        private var collecting = false

        init(shared: [String]) { self.shared = shared }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch element {
            case "row": row = [:]; column = 0
            case "c":
                if let ref = attributes["r"] {
                    column = 0
                    for byte in ref.utf8.prefix(while: { (65...90).contains($0) }) {
                        column = column * 26 + Int(byte) - 64
                        if column > 16384 { parser.abortParsing(); return }
                    }
                    column -= 1
                }
                type = attributes["t"] ?? ""
                value = ""
            case "si": value = ""
            case "v", "t": collecting = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters text: String) {
            if collecting { value += text }
        }
        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "v", "t": collecting = false
            case "si": strings.append(value)
            case "c":
                if type == "s" {
                    guard let index = Int(value), shared.indices.contains(index) else { parser.abortParsing(); return }
                    row[column] = shared[index]
                } else { row[column] = value }
                column += 1
            case "row": rows.append(row)
            default: break
            }
        }
    }
}
