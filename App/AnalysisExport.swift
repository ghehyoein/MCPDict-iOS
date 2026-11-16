import SwiftUI
import UniformTypeIdentifiers

enum AnalysisCSV {
    static func correspondences(_ links: [CorrespondenceLink], left: String, right: String, mode: String) -> String {
        let header = [ui("語言") + " 1", ui("語言") + " 2", ui("今音觀察維度"), ui("發音") + " 1", ui("發音") + " 2", ui("字數"), ui("例字")]
        let rows = links.map { [left, right, mode, $0.left, $0.right, String($0.chars.count), $0.chars.joined(separator: " ")] }
        return EvolutionExportDocument.encode([header] + rows)
    }
    static func soundClasses(_ groups: [SoundClass], characters: [String], mode: String, colors: [String: String]) -> String {
        let header = [ui("漢字"), ui("今音觀察維度"), ui("單字音類"), ui("語言"), ui("方案顏色")]
        let rows = groups.flatMap { group in
            group.names.map { [characters.joined(separator: " "), mode, group.value, $0, colors[group.value] ?? "#0072B2"] }
        }
        return EvolutionExportDocument.encode([header] + rows)
    }
}

struct AnalysisImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// Draw the whole diagram, not just the visible scroll window. Limit pixel height
// to bound memory use for full-syllable analyses containing thousands of nodes.
enum SankeyImageExport {
    static func png(links: [CorrespondenceLink], left: String, right: String, mode: String) -> Data {
        let a = Array(Set(links.map(\.left))).sorted(), b = Array(Set(links.map(\.right))).sorted()
        let height = max(360, CGFloat(max(a.count, b.count)) * 36)
        let size = CGSize(width: 800, height: height + 120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, 8192 / size.height)
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.white.setFill(); output.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: UIColor.black]
            (left as NSString).draw(in: CGRect(x: 16, y: 12, width: 370, height: 70), withAttributes: title)
            (right as NSString).draw(in: CGRect(x: 414, y: 12, width: 370, height: 70), withAttributes: title)
            (mode as NSString).draw(in: CGRect(x: 16, y: 84, width: 768, height: 28), withAttributes: title)
            let total = max(1, links.reduce(0) { $0 + $1.chars.count })
            let scale = max(1, height - CGFloat(max(a.count, b.count)) * 8) / CGFloat(total)
            func starts(_ values: [String], key: KeyPath<CorrespondenceLink, String>) -> [String: CGFloat] {
                let counts = Dictionary(grouping: links, by: { $0[keyPath: key] }).mapValues { $0.reduce(0) { $0 + $1.chars.count } }
                var y: CGFloat = 116, result = [String: CGFloat]()
                for value in values { result[value] = y; y += CGFloat(counts[value] ?? 0) * scale + 8 }
                return result
            }
            let startA = starts(a, key: \.left), startB = starts(b, key: \.right)
            var offsetA = startA, offsetB = startB
            for (index, link) in links.enumerated() {
                let y1 = offsetA[link.left] ?? 116, y2 = offsetB[link.right] ?? 116
                let bandHeight = CGFloat(link.chars.count) * scale
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 190, y: y1))
                path.addCurve(to: CGPoint(x: 610, y: y2), controlPoint1: CGPoint(x: 390, y: y1), controlPoint2: CGPoint(x: 410, y: y2))
                path.addLine(to: CGPoint(x: 610, y: y2 + bandHeight))
                path.addCurve(to: CGPoint(x: 190, y: y1 + bandHeight), controlPoint1: CGPoint(x: 410, y: y2 + bandHeight), controlPoint2: CGPoint(x: 390, y: y1 + bandHeight))
                path.close()
                UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.65, brightness: 0.8, alpha: 0.6).setFill(); path.fill()
                offsetA[link.left, default: 116] += bandHeight; offsetB[link.right, default: 116] += bandHeight
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
            let labels: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black]
            var leftLabels = labels; leftLabels[.paragraphStyle] = paragraph
            for value in a { (value as NSString).draw(in: CGRect(x: 8, y: startA[value] ?? 116, width: 174, height: 36), withAttributes: leftLabels) }
            for value in b { (value as NSString).draw(in: CGRect(x: 618, y: startB[value] ?? 116, width: 174, height: 36), withAttributes: labels) }
        }
        return image.pngData() ?? Data()
    }
}
