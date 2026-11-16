import SwiftUI
import UniformTypeIdentifiers

enum AnalysisCSV {
    static func correspondences(_ links: [CorrespondenceLink], languages: [String], mode: String) -> String {
        let header = [ui("語言") + " 1", ui("語言") + " 2", ui("今音觀察維度"), ui("發音") + " 1", ui("發音") + " 2", ui("字數"), ui("例字")]
        let rows = links.filter { $0.stage >= 0 && $0.stage + 1 < languages.count }.map {
            [languages[$0.stage], languages[$0.stage + 1], mode, $0.left, $0.right, String($0.chars.count), $0.chars.joined(separator: " ")]
        }
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

struct AnalysisResultDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// Export every column. Bound both dimensions and total pixels when the user
// selects many languages; this does not cap or omit languages or CSV rows.
enum SankeyImageExport {
    static func png(links: [CorrespondenceLink], languages: [String], mode: String) -> Data {
        let layout = CorrespondenceLayout(links: links, languages: languages)
        let size = CGSize(width: layout.size.width, height: layout.size.height + 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, 8192 / size.width, 8192 / size.height, sqrt(16_000_000 / (size.width * size.height)))
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.white.setFill(); output.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.black]
            (mode as NSString).draw(in: CGRect(x: 16, y: 8, width: size.width - 32, height: 28), withAttributes: title)
            output.cgContext.translateBy(x: 0, y: 40)
            for (index, band) in layout.bands.enumerated() {
                output.cgContext.setFillColor(UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.65, brightness: 0.8, alpha: 0.6).cgColor)
                output.cgContext.addPath(band.path); output.cgContext.fillPath()
            }
            for (index, name) in languages.enumerated() {
                (name as NSString).draw(in: CGRect(x: CorrespondenceLayout.x(index), y: 12, width: CorrespondenceLayout.columnWidth, height: 64), withAttributes: title)
            }
            let labels: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
            for node in layout.nodes {
                (node.value as NSString).draw(in: node.rect, withAttributes: labels)
            }
        }
        return image.pngData() ?? Data()
    }
}
