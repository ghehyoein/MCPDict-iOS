import UIKit
let exportFormat: UIGraphicsImageRendererFormat = { let f = UIGraphicsImageRendererFormat(); f.scale = 20; f.opaque = false; return f }()
import UIKit

enum OldIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26), format: exportFormat).image { _ in
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
import UIKit

enum NewIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26), format: exportFormat).image { _ in
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

class Delegate: UIResponder, UIApplicationDelegate {
 var window: UIWindow?
 func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
  UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
   let original = UIGraphicsImageRenderer(size: CGSize(width:26,height:26), format:exportFormat).image { _ in
    let book=UIImage(systemName:"character.book.closed", withConfiguration:UIImage.SymbolConfiguration(pointSize:24,weight:.regular))!
    let scale=min(26/book.size.width,26/book.size.height)
    let size=CGSize(width:book.size.width*scale,height:book.size.height*scale)
    book.withTintColor(.black,renderingMode:.alwaysOriginal).draw(in:CGRect(x:(26-size.width)/2,y:(26-size.height)/2,width:size.width,height:size.height))
   }
   let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
   for (name,img) in [("01-original-A",original),("02-book-yin",OldIcon.image),("03-centered-yin",NewIcon.image)] {
    try! img.pngData()!.write(to:dir.appendingPathComponent(name+".png"))
   }
   try! Data("done".utf8).write(to:dir.appendingPathComponent("done"))
  }
  window=UIWindow(frame:UIScreen.main.bounds); window?.rootViewController=UIViewController(); window?.makeKeyAndVisible()
  return true
 }
}
UIApplicationMain(CommandLine.argc,CommandLine.unsafeArgv,nil,NSStringFromClass(Delegate.self))
