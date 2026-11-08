import UIKit

enum DictionaryTabIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
        UIColor.label.setStroke()
        let cover = CGRect(x: 6, y: 2, width: 18, height: 20)
        let outline = UIBezierPath(roundedRect: cover, cornerRadius: 1.8)
        outline.lineWidth = 1.5; outline.stroke()
        let spine = UIBezierPath()
        spine.move(to: CGPoint(x: 6, y: 4))
        spine.addLine(to: CGPoint(x: 3, y: 5))
        spine.addLine(to: CGPoint(x: 3, y: 22))
        spine.addQuadCurve(to: CGPoint(x: 6, y: 24), controlPoint: CGPoint(x: 3, y: 24))
        spine.addLine(to: CGPoint(x: 23, y: 24))
        spine.lineWidth = 1.5; spine.lineCapStyle = .round; spine.lineJoinStyle = .round; spine.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.label]
        let text = "音" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: cover.midX - size.width / 2, y: cover.midY - size.height / 2), withAttributes: attributes)
    }.withRenderingMode(.alwaysTemplate)
}
