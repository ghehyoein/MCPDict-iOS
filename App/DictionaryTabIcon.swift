import UIKit

enum DictionaryTabIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        if let book = UIImage(systemName: "book.closed", withConfiguration: config) {
            let scale = min(26 / book.size.width, 26 / book.size.height)
            let size = CGSize(width: book.size.width * scale, height: book.size.height * scale)
            book.withTintColor(.label, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (26 - size.width) / 2, y: (26 - size.height) / 2, width: size.width, height: size.height))
        }
        ("音" as NSString).draw(at: CGPoint(x: 9, y: 5), withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.label])
    }.withRenderingMode(.alwaysTemplate)
}
