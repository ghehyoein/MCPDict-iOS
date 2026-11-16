import CoreGraphics

// Share geometry between the interactive diagram and PNG export. Incoming and
// outgoing ribbons use the same node; unequal totals (missing data/polyphony)
// leave space rather than inventing correspondences to balance the flows.
struct CorrespondenceLayout {
    struct Node: Identifiable {
        let column: Int
        let value: String
        let rect: CGRect
        var id: String { String(column) + "\u{0}" + value }
    }
    struct Band {
        let link: CorrespondenceLink
        let path: CGPath
    }
    static let columnWidth: CGFloat = 140
    static func x(_ column: Int) -> CGFloat { 16 + CGFloat(column) * 340 }
    let nodes: [Node]
    let bands: [Band]
    let size: CGSize

    init(links: [CorrespondenceLink], languages: [String]) {
        let count = languages.count
        let valid = links.filter { $0.stage >= 0 && $0.stage + 1 < count }
        var incoming = Array(repeating: [String: Int](), count: count)
        var outgoing = incoming
        for link in valid {
            outgoing[link.stage][link.left, default: 0] += link.chars.count
            incoming[link.stage + 1][link.right, default: 0] += link.chars.count
        }
        let values = (0..<count).map { Set(incoming[$0].keys).union(outgoing[$0].keys).sorted() }
        let weights = (0..<count).map { column in
            Dictionary(uniqueKeysWithValues: values[column].map { value in
                (value, max(incoming[column][value] ?? 0, outgoing[column][value] ?? 0))
            })
        }
        let maximumNodes = values.map(\.count).max() ?? 0
        let maximumWeight = max(1, weights.map { $0.values.reduce(0, +) }.max() ?? 0)
        let targetHeight = max(360, CGFloat(maximumNodes) * 36)
        let scale = max(1, targetHeight - CGFloat(maximumNodes) * 8) / CGFloat(maximumWeight)
        var starts = Array(repeating: [String: CGFloat](), count: count)
        var nodes = [Node](), height: CGFloat = 440
        for column in 0..<count {
            var y: CGFloat = 80
            for value in values[column] {
                let nodeHeight = max(28, CGFloat(weights[column][value] ?? 0) * scale)
                starts[column][value] = y
                nodes.append(Node(column: column, value: value,
                    rect: CGRect(x: Self.x(column), y: y, width: Self.columnWidth, height: nodeHeight)))
                y += nodeHeight + 8
            }
            height = max(height, y + 16)
        }
        var from = starts, to = starts
        self.bands = valid.map { link in
            let a = link.stage, b = a + 1
            let x1 = Self.x(a) + Self.columnWidth, x2 = Self.x(b)
            let y1 = from[a][link.left] ?? 80, y2 = to[b][link.right] ?? 80
            let thickness = CGFloat(link.chars.count) * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addCurve(to: CGPoint(x: x2, y: y2), control1: CGPoint(x: x1 + 100, y: y1), control2: CGPoint(x: x2 - 100, y: y2))
            path.addLine(to: CGPoint(x: x2, y: y2 + thickness))
            path.addCurve(to: CGPoint(x: x1, y: y1 + thickness), control1: CGPoint(x: x2 - 100, y: y2 + thickness), control2: CGPoint(x: x1 + 100, y: y1 + thickness))
            path.closeSubpath()
            from[a][link.left, default: 80] += thickness
            to[b][link.right, default: 80] += thickness
            return Band(link: link, path: path)
        }
        self.nodes = nodes
        self.size = CGSize(width: max(550, Self.x(max(0, count - 1)) + Self.columnWidth + 16), height: height)
    }
}
