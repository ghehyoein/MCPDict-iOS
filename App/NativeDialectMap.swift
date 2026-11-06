import SwiftUI
import MapKit

struct NativeDialectMap: UIViewRepresentable {
    let points: [DialectPoint]
    let fit: Int
    var fontSize: Double = 17
    var nameSize: Double = 14
    var mapStyle: String = "standard"
    var centerChanged: (TableLocation) -> Void = { _ in }
    var copied: () -> Void = {}
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
        context.coordinator.copied = copied
        context.coordinator.centerChanged = centerChanged
        let type = (BaseMapStyle(rawValue: mapStyle) ?? .standard).type
        if map.mapType != type { map.mapType = type }
        context.coordinator.update(map, points: points, fit: fit, fontSize: fontSize, nameSize: nameSize)
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
        var nameSize = 14.0
        var centerChanged: (TableLocation) -> Void = { _ in }
        var copied: () -> Void = {}
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let center = TableLocation(longitude: mapView.centerCoordinate.longitude, latitude: mapView.centerCoordinate.latitude)
            DispatchQueue.main.async { [weak self] in self?.centerChanged(center) }
        }
        func update(_ map: MKMapView, points: [DialectPoint], fit: Int, fontSize: Double = 17, nameSize: Double = 14) {
            let fontChanged = self.fontSize != fontSize || self.nameSize != nameSize
            if self.points != points || fontChanged {
                self.nameSize = nameSize
                self.fontSize = fontSize
                self.points = points
                let wanted = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
                var retained = Set<String>()
                var removed = [PointAnnotation]()
                for annotation in map.annotations.compactMap({ $0 as? PointAnnotation }) {
                    if !fontChanged, wanted[annotation.point.id] == annotation.point { retained.insert(annotation.point.id) }
                    else { removed.append(annotation) }
                }
                map.removeAnnotations(removed)
                map.addAnnotations(points.filter { !retained.contains($0.id) }.map(PointAnnotation.init))
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
            view.copied = copied
            view.configure(point.point, fontSize: fontSize, nameSize: nameSize) { [weak self] in self?.choose(point.point.id) }
            return view
        }

    }
}


final class LabelAnnotationView: MKAnnotationView, UIGestureRecognizerDelegate {
    let nameButton = UIButton(type: .system)
    let readingButton = UIButton(type: .system)
    var copied: () -> Void = {}
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let gradient = CAGradientLayer()
    private var choose: (() -> Void)?
    private var rawReading = ""
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // Only the two map sliders size annotation text; map controls keep their normal traits.
        traitOverrides.preferredContentSizeCategory = .large
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = false
        readingButton.titleLabel?.adjustsFontForContentSizeCategory = false
        nameButton.layer.insertSublayer(gradient, at: 0)
        nameButton.layer.cornerRadius = 5; nameButton.clipsToBounds = true
        nameButton.setTitleColor(.white, for: .normal)
        readingButton.setTitleColor(.label, for: .normal)
        readingButton.backgroundColor = .clear
        blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = 4; blur.clipsToBounds = true
        insertSubview(blur, at: 0)
        readingButton.layer.cornerRadius = 3
        readingButton.titleLabel?.numberOfLines = 0
        addSubview(nameButton); addSubview(readingButton)
        nameButton.addTarget(self, action: #selector(openDetails), for: .touchUpInside)
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityElements = [readingButton, nameButton]
        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.5
        press.cancelsTouchesInView = false
        press.delegate = self
        addGestureRecognizer(press)
        readingButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: ui("複製讀音"), target: self, selector: #selector(accessibilityCopy))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // MapKit handles annotation selection itself. Explicit child hit testing keeps the
    // pronunciation and name controls interactive, including overlapping label bounds.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        for control in [readingButton, nameButton] where !control.isHidden {
            if let hit = control.hitTest(convert(point, to: control), with: event) { return hit }
        }
        return nil
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !readingButton.isHidden && readingButton.frame.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func accessibilityCopy() -> Bool { copyReading(); return !rawReading.isEmpty }
    @objc private func openDetails() { choose?() }
    @objc private func longPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { copyReading() }
    }
    func copyReading() {
        guard !rawReading.isEmpty else { return }
        UIPasteboard.general.string = rawReading
        #if DEBUG
        // XCTest waits for MapKit to idle, which can outlast the one-second hint.
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { readingButton.accessibilityValue = UIPasteboard.general.string }
        #endif
        copied()
        UIAccessibility.post(notification: .announcement, argument: ui("已複製讀音"))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func configure(_ point: DialectPoint, fontSize: Double, nameSize: Double = 14, choose: @escaping () -> Void) {
        self.choose = choose; rawReading = point.reading
        nameButton.setTitle(point.name, for: .normal)
        nameButton.accessibilityLabel = point.name
        nameButton.titleLabel?.font = .systemFont(ofSize: nameSize)
        let colors = TableColors.hexes(point.color)
        nameButton.backgroundColor = TableColors.uiColor(colors.first ?? "#008080")
        gradient.colors = (colors.count == 1 ? colors + colors : colors).map { TableColors.uiColor($0).cgColor }
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
        readingButton.accessibilityIdentifier = "map-reading-" + point.id
        readingButton.accessibilityLabel = point.reading
        readingButton.accessibilityHint = ui("長按複製讀音")
        readingButton.isHidden = point.reading.isEmpty
        let nameButtonSize = nameButton.sizeThatFits(CGSize(width: 260, height: 100))
        let readingRect = text.boundingRect(with: CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let nameWidth: CGFloat = nameButtonSize.width + 12, nameHeight: CGFloat = max(nameButtonSize.height, CGFloat(nameSize) * 1.4)
        let readingWidth: CGFloat = min(268, ceil(readingRect.width) + 8)
        let readingHeight: CGFloat = point.reading.isEmpty ? 0 : ceil(readingRect.height) + 8
        let width = max(nameWidth, readingWidth)
        bounds = CGRect(x: 0, y: 0, width: width, height: nameHeight + readingHeight)
        nameButton.frame = CGRect(x: (width-nameWidth)/2, y: readingHeight, width: nameWidth, height: nameHeight)
        readingButton.frame = CGRect(x: (width-readingWidth)/2, y: 0, width: readingWidth, height: readingHeight)
        blur.frame = readingButton.frame; blur.isHidden = readingButton.isHidden
        gradient.frame = nameButton.bounds
        collisionMode = .rectangle
    }
}
