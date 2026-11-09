import UIKit

enum DictionaryTabIcon {
    static let image: UIImage = {
        guard let image = UIImage(named: "DictionaryTab"), let pixels = image.cgImage else {
            return UIImage()
        }
        // Keep the approved artwork intact and give it the existing 26-point tab size.
        return UIImage(cgImage: pixels, scale: CGFloat(pixels.width) / 26,
                       orientation: image.imageOrientation)
            .withRenderingMode(.alwaysTemplate)
    }()
}
