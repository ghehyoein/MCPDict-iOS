import SwiftUI
import MapKit

struct NativeDialectMap: UIViewRepresentable {
    let points: [DialectPoint]
    let fit: Int
    var fontSize: Double = 17
    let choose: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34, longitude: 108), span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 48)), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.choose = choose
        context.coordinator.update(map, points: points, fit: fit, fontSize: fontSize)
    }
    final class PointAnnotation: NSObject, MKAnnotation {
        let point: DialectPoint
        var coordinate: CLLocationCoordinate2D { .init(latitude: point.latitude, longitude: point.longitude) }
        var title: String? { point.name }
        var subtitle: String? { point.reading }
        init(_ point: DialectPoint) { self.point = point }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var points = [DialectPoint]()
        var fit = 0
        var fontSize = 17.0
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }
        func update(_ map: MKMapView, points: [DialectPoint], fit: Int, fontSize: Double = 17) {
            if self.points != points || self.fontSize != fontSize {
                self.fontSize = fontSize
                self.points = points
                map.removeAnnotations(map.annotations)
                map.addAnnotations(points.map(PointAnnotation.init))
            }
            if self.fit != fit {
                self.fit = fit
                if !map.annotations.isEmpty { map.showAnnotations(map.annotations, animated: true) }
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "dialect-label") as? LabelAnnotationView) ?? LabelAnnotationView(annotation: annotation, reuseIdentifier: "dialect-label")
            view.annotation = annotation
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            view.centerOffset = .zero
            view.canShowCallout = false
            view.configure(point.point, fontSize: fontSize) { [weak self] in self?.choose(point.point.id) }
            return view
        }

    }
}


final class LabelAnnotationView: MKAnnotationView {
    let nameButton = UIButton(type: .system)
    let readingButton = UIButton(type: .system)
    private let gradient = CAGradientLayer()
    private var choose: (() -> Void)?
    private var rawReading = ""
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        nameButton.layer.insertSublayer(gradient, at: 0)
        nameButton.layer.cornerRadius = 5; nameButton.clipsToBounds = true
        nameButton.setTitleColor(.white, for: .normal)
        readingButton.setTitleColor(.label, for: .normal)
        readingButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        readingButton.layer.cornerRadius = 3
        readingButton.titleLabel?.numberOfLines = 0
        addSubview(nameButton); addSubview(readingButton)
        nameButton.addTarget(self, action: #selector(openDetails), for: .touchUpInside)
        readingButton.addTarget(self, action: #selector(copyReading), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func openDetails() { choose?() }
    @objc private func copyReading() {
        UIPasteboard.general.string = rawReading
        UIAccessibility.post(notification: .announcement, argument: ui("已複製讀音"))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func configure(_ point: DialectPoint, fontSize: Double, choose: @escaping () -> Void) {
        self.choose = choose; rawReading = point.reading
        nameButton.setTitle(point.name, for: .normal)
        nameButton.accessibilityLabel = point.name
        nameButton.titleLabel?.font = .systemFont(ofSize: fontSize * 0.82)
        gradient.colors = TableColors.hexes(point.color).map { TableColors.uiColor($0).cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5)
        let text = NSMutableAttributedString(string: "")
        let font = UIFont.systemFont(ofSize: fontSize)
        let parts = point.toneParts ?? [.init(id: 0, base: point.reading, pitch: "", tone: "", stacked: false)]
        for part in parts {
            text.append(NSAttributedString(string: part.base, attributes: [.font: font, .foregroundColor: UIColor.label]))
            if part.stacked {
                let tiny = UIFont.systemFont(ofSize: fontSize * 0.55)
                let attrs: [NSAttributedString.Key: Any] = [.font: tiny, .foregroundColor: UIColor.label]
                let width = max((part.pitch as NSString).size(withAttributes: attrs).width, (part.tone as NSString).size(withAttributes: attrs).width) + 2
                let attachment = NSTextAttachment()
                attachment.image = UIGraphicsImageRenderer(size: CGSize(width: width, height: fontSize * 1.35)).image { _ in
                    (part.pitch as NSString).draw(at: .zero, withAttributes: attrs)
                    (part.tone as NSString).draw(at: CGPoint(x: 0, y: fontSize * 0.65), withAttributes: attrs)
                }
                attachment.bounds = CGRect(x: 0, y: -fontSize * 0.25, width: width, height: fontSize * 1.35)
                text.append(NSAttributedString(attachment: attachment))
            } else { text.append(NSAttributedString(string: part.pitch + part.tone, attributes: [.font: font, .foregroundColor: UIColor.label])) }
        }
        readingButton.setAttributedTitle(text, for: .normal)
        readingButton.accessibilityLabel = point.reading
        readingButton.accessibilityHint = ui("點擊複製讀音")
        readingButton.isHidden = point.reading.isEmpty
        let nameSize = nameButton.sizeThatFits(CGSize(width: 260, height: 100))
        let readingRect = text.boundingRect(with: CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let nameWidth: CGFloat = nameSize.width + 12, nameHeight: CGFloat = max(nameSize.height, CGFloat(fontSize) * 1.4)
        let readingWidth: CGFloat = min(268, ceil(readingRect.width) + 8)
        let readingHeight: CGFloat = point.reading.isEmpty ? 0 : ceil(readingRect.height) + 8
        let width = max(nameWidth, readingWidth)
        bounds = CGRect(x: 0, y: 0, width: width, height: nameHeight + readingHeight)
        nameButton.frame = CGRect(x: (width-nameWidth)/2, y: 0, width: nameWidth, height: nameHeight)
        readingButton.frame = CGRect(x: (width-readingWidth)/2, y: nameHeight, width: readingWidth, height: readingHeight)
        gradient.frame = nameButton.bounds
        collisionMode = .rectangle
    }
}

