import SwiftUI
import MapKit
import ObjectiveC

struct NativeDialectMap: UIViewRepresentable {
    let points: [DialectPoint]
    let fit: Int
    var revision: UUID? = nil
    var fontSize: Double = 16
    var readingSize: Double = 16
    var mapStyle: String = "standard"
    var centerChanged: (TableLocation) -> Void = { _ in }
    let choose: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }
    func makeUIView(context: Context) -> MKMapView {
        let map = CachedAccessibilityMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34, longitude: 108), span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 48)), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.choose = choose
        context.coordinator.centerChanged = centerChanged
        let type = (BaseMapStyle(rawValue: mapStyle) ?? .standard).type
        if map.mapType != type { map.mapType = type }
        context.coordinator.update(map, points: points, fit: fit, fontSize: fontSize, readingSize: readingSize, revision: revision)
    }
    final class PointAnnotation: NSObject, MKAnnotation {
        var point: DialectPoint
        var coordinate: CLLocationCoordinate2D { .init(latitude: point.latitude, longitude: point.longitude) }
        var title: String? { point.name }
        var subtitle: String? { point.reading }
        init(_ point: DialectPoint) { self.point = point }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var points = [DialectPoint]()
        private var revision: UUID?
        var fit = 0
        var fontSize = 16.0
        var readingSize = 16.0
        var centerChanged: (TableLocation) -> Void = { _ in }
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            (mapView as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
            let center = TableLocation(longitude: mapView.centerCoordinate.longitude, latitude: mapView.centerCoordinate.latitude)
            DispatchQueue.main.async { [weak self] in self?.centerChanged(center) }
        }
        func update(_ map: MKMapView, points: [DialectPoint], fit: Int, fontSize: Double = 16, readingSize: Double = 16, revision: UUID? = nil) {
            let fontChanged = self.fontSize != fontSize || self.readingSize != readingSize
            let contentChanged = revision.map { $0 != self.revision } ?? (self.points != points)
            if contentChanged || fontChanged {
                self.fontSize = fontSize; self.readingSize = readingSize
                self.points = points; self.revision = revision
                let wanted = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
                var retained = Set<String>()
                var removed = [PointAnnotation]()
                for annotation in map.annotations.compactMap({ $0 as? PointAnnotation }) {
                    guard let next = wanted[annotation.point.id], next.latitude == annotation.point.latitude,
                          next.longitude == annotation.point.longitude else { removed.append(annotation); continue }
                    retained.insert(next.id)
                    let changed = annotation.point != next
                    annotation.point = next
                    if changed || fontChanged, let view = map.view(for: annotation) as? LabelAnnotationView {
                        view.configure(next, fontSize: readingSize, labelSize: fontSize) { [weak self] in self?.choose(next.id) }
                    }
                }
                if !removed.isEmpty { map.removeAnnotations(removed) }
                let added = points.filter { !retained.contains($0.id) }.map(PointAnnotation.init)
                if !added.isEmpty { map.addAnnotations(added) }
                (map as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
            }
            if self.fit != fit {
                self.fit = fit
                if let rect = Self.automaticMapRect(points: points, viewport: map.bounds.size) {
                    map.setVisibleMapRect(rect, animated: true)
                }
            }
        }
        // Limit automatic fitting only; user gestures can still zoom in freely.
        // Match the device viewport so its north-to-south extent is at least ~500 km.
        static func automaticMapRect(points: [DialectPoint], viewport: CGSize) -> MKMapRect? {
            guard !points.isEmpty else { return nil }
            let locations = points.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            let minX = locations.map(\.x).min()!, maxX = locations.map(\.x).max()!
            let minY = locations.map(\.y).min()!, maxY = locations.map(\.y).max()!
            let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let aspect = max(1, viewport.width) / max(1, viewport.height)
            let minimumHeight = 500_000 * MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)
            // Leave breathing room around spread-out results, without adding it to
            // the minimum scale for a single point or a dense cluster.
            let height = max(minimumHeight, (maxY - minY) * 1.25, (maxX - minX) * 1.25 / aspect)
            let width = height * aspect
            return MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        }
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            (mapView as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            (mapView as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "dialect-label") as? LabelAnnotationView) ?? LabelAnnotationView(annotation: annotation, reuseIdentifier: "dialect-label")
            view.annotation = annotation
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            view.centerOffset = .zero
            view.canShowCallout = false
            view.configure(point.point, fontSize: readingSize, labelSize: fontSize) { [weak self] in self?.choose(point.point.id) }
            return view
        }

    }
}


// MapKit rebuilds its native accessibility array for every element-at-index
// request. With thousands of labels, one traversal repeats that full scan
// thousands of times. Reuse the exact native elements until the map changes.
final class CachedAccessibilityMapView: MKMapView {
    private var accessibilitySnapshot: [Any]?
    private var accessibilityIndices = [ObjectIdentifier: Int]()
    private var hasAccessibilitySnapshot = false
    private func prepareAccessibilitySnapshot() {
        guard !hasAccessibilitySnapshot else { return }
        // Transparent native containers also recompute their full child array
        // for each indexed access. Preserve their actual accessible controls.
        var flattened = [Any]()
        var seen = Set<ObjectIdentifier>()
        func append(_ element: Any) {
            if let view = element as? UIView {
                guard view !== self, seen.insert(ObjectIdentifier(view)).inserted else { return }
                if !view.isAccessibilityElement, let children = view.accessibilityElements, !children.isEmpty {
                    for child in children { append(child) }
                    return
                }
            }
            flattened.append(element)
        }
        if let elements = super.accessibilityElements {
            for element in elements { append(element) }
            accessibilitySnapshot = flattened
        } else { accessibilitySnapshot = nil }
        accessibilityIndices.removeAll(keepingCapacity: true)
        for (index, element) in flattened.enumerated() {
            if let object = element as? NSObject {
                let key = ObjectIdentifier(object)
                if accessibilityIndices[key] == nil { accessibilityIndices[key] = index }
            }
        }
        hasAccessibilitySnapshot = true
    }
    override var accessibilityElements: [Any]? {
        get { prepareAccessibilitySnapshot(); return accessibilitySnapshot }
        set { super.accessibilityElements = newValue; invalidateAccessibilitySnapshot() }
    }
    // NSObject's default indexed accessor fetches and reconnects the entire
    // array on every index. These public container methods keep each access O(1).
    override func accessibilityElementCount() -> Int {
        prepareAccessibilitySnapshot()
        return accessibilitySnapshot?.count ?? 0
    }
    override func accessibilityElement(at index: Int) -> Any? {
        prepareAccessibilitySnapshot()
        guard let elements = accessibilitySnapshot, elements.indices.contains(index) else { return nil }
        return elements[index]
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        prepareAccessibilitySnapshot()
        guard let object = element as? NSObject else { return NSNotFound }
        return accessibilityIndices[ObjectIdentifier(object)] ?? NSNotFound
    }
    func invalidateAccessibilitySnapshot() {
        hasAccessibilitySnapshot = false
        accessibilitySnapshot = nil
        accessibilityIndices.removeAll(keepingCapacity: true)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateAccessibilitySnapshot()
    }
}

final class LabelAnnotationView: MKAnnotationView, UIGestureRecognizerDelegate {
    let nameButton = UIButton(type: .system)
    private(set) var readingView: UITextView?
    private var readingBlur: UIVisualEffectView?
    private var readingPreview: MapReadingPreview?
    private var renderedReading = NSAttributedString(string: "")
    private var readingFrame = CGRect.zero
    private var readingNeedsScroll = false
    private func ensureReadingPreview() {
        guard readingPreview == nil else { return }
        let preview = MapReadingPreview()
        preview.backgroundColor = .clear
        preview.clipsToBounds = true
        preview.contentMode = .redraw
        preview.isAccessibilityElement = true
        preview.accessibilityTraits = .staticText
        preview.activate = { [weak self] in
            guard let self else { return false }
            return self.readingText.becomeFirstResponder()
        }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = 4; blur.clipsToBounds = true
        insertSubview(blur, at: 0); addSubview(preview)
        readingPreview = preview; readingBlur = blur
    }
    // TextKit and native selection machinery are needed only for a touched label.
    // Hit testing creates the text view before UIKit delivers that same touch,
    // preserving the first long press and native selection gestures.
    var readingText: UITextView {
        if let readingView { return readingView }
        ensureReadingPreview()
        let text = UITextView()
        text.adjustsFontForContentSizeCategory = false
        text.isEditable = false; text.isSelectable = true
        text.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        text.textContainer.lineFragmentPadding = 0
        text.textColor = .label; text.backgroundColor = .clear
        text.layer.cornerRadius = 3
        text.textContainer.maximumNumberOfLines = 0
        text.textContainer.lineBreakMode = .byCharWrapping
        text.attributedText = renderedReading
        text.frame = readingFrame; text.isScrollEnabled = readingNeedsScroll
        text.accessibilityIdentifier = readingPreview?.accessibilityIdentifier
        text.accessibilityLabel = readingPreview?.accessibilityLabel
        addSubview(text); readingView = text; readingPreview?.isHidden = true
        if window != nil { MapTextGestureGate.install(above: self) }
        accessibilityElements = [text, nameButton]
        (superviewOfMap() as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
        return text
    }
    private func superviewOfMap() -> MKMapView? {
        var parent = superview
        while let view = parent {
            if let map = view as? MKMapView { return map }
            parent = view.superview
        }
        return nil
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        readingView?.resignFirstResponder(); readingView?.removeFromSuperview(); readingView = nil
        readingPreview?.isHidden = false
        if let readingPreview { accessibilityElements = [readingPreview, nameButton] }
    }
    private let gradient = CAGradientLayer()
    private var choose: (() -> Void)?
    private var previousReading: String?
    private var previousParts: [ToneDisplay.Part]?
    private var previousFontSize: Double?
    private var cachedReadingRect = CGRect.zero
    private var previousColor: String?
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // Only the map slider sizes annotation text; map controls keep their normal traits.
        traitOverrides.preferredContentSizeCategory = .large
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = false
        nameButton.layer.insertSublayer(gradient, at: 0)
        nameButton.layer.cornerRadius = 5; nameButton.clipsToBounds = true
        nameButton.setTitleColor(.white, for: .normal)
        addSubview(nameButton)
        nameButton.addTarget(self, action: #selector(openDetails), for: .touchUpInside)
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityElements = [nameButton]

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && readingView != nil { MapTextGestureGate.install(above: self) }
    }
    // MapKit handles annotation selection itself. Explicit child hit testing keeps the
    // pronunciation and name controls interactive, including overlapping label bounds.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        let selecting = readingView?.isFirstResponder == true
        // Reject off-label touches in O(1), without walking TextKit descendants.
        guard bounds.contains(point) || selecting else { return nil }
        if !readingFrame.isEmpty, readingFrame.contains(point) || selecting {
            let text = readingText
            if let hit = text.hitTest(convert(point, to: text), with: event) { return hit }
        }
        guard !nameButton.isHidden else { return nil }
        return nameButton.hitTest(convert(point, to: nameButton), with: event)
    }
    @objc private func openDetails() { choose?() }
    func configure(_ point: DialectPoint, fontSize: Double, labelSize: Double = 16, choose: @escaping () -> Void) {
        self.choose = choose
        if nameButton.currentTitle != point.name { nameButton.setTitle(point.name, for: .normal) }
        nameButton.accessibilityLabel = point.name
        nameButton.accessibilityIdentifier = "map-name-" + point.id
        if nameButton.titleLabel?.font.pointSize != CGFloat(labelSize) { nameButton.titleLabel?.font = .systemFont(ofSize: labelSize) }
        if previousColor != point.color {
        previousColor = point.color
        let colors = TableColors.hexes(point.color)
        nameButton.backgroundColor = TableColors.uiColor(colors.first ?? "#008080")
        gradient.colors = (colors.count == 1 ? colors + colors : colors).map { TableColors.uiColor($0).cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5)
        }
        if point.reading.isEmpty {
            previousReading = nil
            readingView?.removeFromSuperview(); readingBlur?.removeFromSuperview(); readingPreview?.removeFromSuperview()
            readingView = nil; readingBlur = nil; readingPreview = nil
            renderedReading = NSAttributedString(string: ""); readingFrame = .zero
            previousParts = nil
            let size = nameButton.sizeThatFits(CGSize(width: 260, height: 100))
            bounds = CGRect(x: 0, y: 0, width: size.width + 12, height: max(size.height, CGFloat(labelSize) * 1.4))
            nameButton.frame = bounds; gradient.frame = nameButton.bounds
            accessibilityElements = [nameButton]
            collisionMode = .rectangle
            return
        }
        ensureReadingPreview()
        if let readingView { accessibilityElements = [readingView, nameButton] }
        else if let readingPreview { accessibilityElements = [readingPreview, nameButton] }
        let textChanged = previousReading != point.reading || previousParts != point.toneParts || previousFontSize != fontSize
        if textChanged {
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        let contentChanged = previousReading != point.reading
        renderedReading = text
        if let readingView {
            let selection = readingView.selectedRange
            readingView.attributedText = text
            if !contentChanged && NSMaxRange(selection) <= text.length { readingView.selectedRange = selection }
            if contentChanged { readingView.setContentOffset(.zero, animated: false) }
        }
        previousReading = point.reading; previousParts = point.toneParts; previousFontSize = fontSize
        let range = (text.string as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(text.length, 1024)))
        let previewText = text.attributedSubstring(from: range)
        readingPreview?.text = previewText
        cachedReadingRect = previewText.boundingRect(with: CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        for view in [readingPreview as UIView?, readingView as UIView?].compactMap({ $0 }) {
            view.accessibilityIdentifier = "map-reading-" + point.id
            view.accessibilityLabel = point.reading
        }
        let nameButtonSize = nameButton.sizeThatFits(CGSize(width: 260, height: 100))
        // Size only the viewport; the text view retains the entire selectable text.
        let readingRect = cachedReadingRect
        let nameWidth: CGFloat = nameButtonSize.width + 12, nameHeight: CGFloat = max(nameButtonSize.height, CGFloat(labelSize) * 1.4)
        let readingWidth: CGFloat = min(268, ceil(readingRect.width) + 8)
        let readingHeight: CGFloat = point.reading.isEmpty ? 0 : min(180, ceil(readingRect.height) + 8)
        let width = max(nameWidth, readingWidth)
        bounds = CGRect(x: 0, y: 0, width: width, height: nameHeight + readingHeight)
        nameButton.frame = CGRect(x: (width-nameWidth)/2, y: readingHeight, width: nameWidth, height: nameHeight)
        readingFrame = CGRect(x: (width-readingWidth)/2, y: 0, width: readingWidth, height: readingHeight)
        readingNeedsScroll = ceil(readingRect.height) + 8 > readingHeight
        readingPreview?.frame = readingFrame; readingView?.frame = readingFrame
        readingView?.isScrollEnabled = readingNeedsScroll
        readingBlur?.frame = readingFrame
        gradient.frame = nameButton.bounds
        collisionMode = .rectangle
    }
}

/// Preserve MapKit's delegate for every normal gesture, but do not let ancestor
/// map recognizers consume touches belonging to a selectable annotation text view.
private final class MapTextGestureGate: NSObject, UIGestureRecognizerDelegate {
    private static var associationKey: UInt8 = 0
    private weak var original: UIGestureRecognizerDelegate?
    init(original: UIGestureRecognizerDelegate?) { self.original = original }
    static func install(above view: UIView) {
        var parent = view.superview
        while let ancestor = parent {
            for gesture in ancestor.gestureRecognizers ?? [] where !(gesture.delegate is MapTextGestureGate) {
                // UIScrollView requires ownership of its built-in gesture delegates.
                if let scroll = ancestor as? UIScrollView,
                   gesture === scroll.panGestureRecognizer || gesture === scroll.pinchGestureRecognizer { continue }
                let gate = MapTextGestureGate(original: gesture.delegate)
                objc_setAssociatedObject(gesture, &associationKey, gate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                gesture.delegate = gate
            }
            if ancestor is MKMapView { break }
            parent = ancestor.superview
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var ancestor = touch.view
        while let view = ancestor {
            if view is UITextView, view.superview is LabelAnnotationView { return false }
            ancestor = view.superview
        }
        return original?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

// Bounded, inert drawing for untouched results; full text remains available to
// accessibility and is loaded into the native text view on interaction.
private final class MapReadingPreview: UIView {
    var text = NSAttributedString(string: "") { didSet { setNeedsDisplay() } }
    var activate: (() -> Bool)?
    override func draw(_ rect: CGRect) {
        text.draw(with: bounds.insetBy(dx: 4, dy: 4), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { setNeedsDisplay() }
    }
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}
