import UIKit

enum DictionaryTabIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
        UIColor.label.setStroke()
        let cover = UIBezierPath(roundedRect: CGRect(x: 3, y: 1.5, width: 20, height: 23), cornerRadius: 2)
        cover.lineWidth = 1.5; cover.stroke()
        let spine = UIBezierPath(); spine.move(to: CGPoint(x: 6.5, y: 2)); spine.addLine(to: CGPoint(x: 6.5, y: 24))
        spine.lineWidth = 1.2; spine.stroke()
        ("音" as NSString).draw(at: CGPoint(x: 8, y: 5), withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: UIColor.label])
    }.withRenderingMode(.alwaysTemplate)
}
