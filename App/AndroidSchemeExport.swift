import Foundation
import ZIPFoundation

extension AndroidSchemeWorkbook {
    static func write(_ source: CustomLanguageSchemes, root: String) throws -> Data {
        var members = [["語言", "自選分區", "自選顏色"]]
        var groups = [["自選分區", "分區顏色"]]
        var rootColor = ""
        for (index, scheme) in source.schemes.enumerated() where CustomLanguageSchemes.belongs(scheme.name, to: [root]) {
            let path = scheme.name == root ? "" : String(scheme.name.dropFirst(root.count + 1)).replacingOccurrences(of: "－", with: "-")
            if path.isEmpty { rootColor = source.color(at: index) }
            else { groups.append([path, source.color(at: index)]) }
            for language in scheme.languages.sorted() {
                members.append([language, path, scheme.languageColors?[language] ?? ""])
            }
        }
        let sheets = [("語言", members), ("分區", groups), ("方案", [["方案顏色"], [rootColor]])]
        let zip = try ZIPFoundation.Archive(data: Data(), accessMode: .create)
        func add(_ name: String, _ xml: String) throws {
            let data = Data(xml.utf8)
            try zip.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, size in
                data.subdata(in: Int(offset)..<min(data.count, Int(offset) + size))
            }
        }
        let ns = "http://schemas.openxmlformats.org"
        let rel = ns + "/officeDocument/2006/relationships"
        let sheetNS = ns + "/spreadsheetml/2006/main"
        let mime = "application/vnd.openxmlformats-officedocument.spreadsheetml."
        var types = "", names = "", links = ""
        for (i, sheet) in sheets.enumerated() {
            let id = i + 1, path = "worksheets/sheet\(id).xml"
            types += "<Override PartName=\"/xl/\(path)\" ContentType=\"\(mime)worksheet+xml\"/>"
            names += "<sheet name=\"\(sheet.0)\" sheetId=\"\(id)\" r:id=\"rId\(id)\"/>"
            links += "<Relationship Id=\"rId\(id)\" Type=\"\(rel)/worksheet\" Target=\"\(path)\"/>"
            var xml = "<worksheet xmlns=\"\(sheetNS)\"><sheetData>"
            for (r, row) in sheet.1.enumerated() {
                xml += "<row r=\"\(r+1)\">"
                for (c, value) in row.enumerated() {
                    let escaped = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                    xml += "<c r=\"\(["A","B","C"][c])\(r+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
                }
                xml += "</row>"
            }
            try add("xl/" + path, xml + "</sheetData></worksheet>")
        }
        try add("[Content_Types].xml", "<Types xmlns=\"\(ns)/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"\(mime)sheet.main+xml\"/>\(types)</Types>")
        try add("_rels/.rels", "<Relationships xmlns=\"\(ns)/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        try add("xl/workbook.xml", "<workbook xmlns=\"\(sheetNS)\" xmlns:r=\"\(rel)\"><sheets>\(names)</sheets></workbook>")
        try add("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"\(ns)/package/2006/relationships\">\(links)</Relationships>")
        guard let data = zip.data else { throw invalid }
        return data
    }
}
