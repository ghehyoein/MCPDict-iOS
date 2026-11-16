import SwiftUI
import MapKit
import ObjectiveC

enum MapReadingAppearance {
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.30, alpha: 0.92)
            : UIColor.secondarySystemBackground.resolvedColor(with: traits).withAlphaComponent(0.85)
    }
}

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
        private weak var attachedMap: MKMapView?
        private var releasedDrawingBuffers = false
        init(choose: @escaping (String) -> Void) {
            self.choose = choose
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(releaseOffscreenBuffers(_:)),
                name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func releaseOffscreenBuffers(_ notification: Notification) {
            guard let map = attachedMap else { return }
            releasedDrawingBuffers = true
            let nearby = drawingRect(map)
            for annotation in map.annotations {
                guard let point = annotation as? PointAnnotation else { continue }
                (map.view(for: point) as? LabelAnnotationView)?.setDrawingActive(nearby.contains(MKMapPoint(point.coordinate)))
            }
        }
        // Keep a generous border for labels whose anchor is outside the screen.
        // Reclaim pixels only on memory pressure: discarding them after every
        // zoom saves memory but forces large synchronous redraws on the next zoom.
        // MapKit's spatial index restores nearby buffers after a memory warning.
        private func drawingRect(_ map: MKMapView) -> MKMapRect {
            let rect = map.visibleMapRect
            return rect.insetBy(dx: -rect.width * 300 / max(1, map.bounds.width),
                                dy: -rect.height * 300 / max(1, map.bounds.height))
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard releasedDrawingBuffers else { return }
            for annotation in mapView.annotations(in: drawingRect(mapView)) {
                guard let point = annotation.base as? PointAnnotation else { continue }
                (mapView.view(for: point) as? LabelAnnotationView)?.setDrawingActive(true)
            }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            mapViewDidChangeVisibleRegion(mapView)
            (mapView as? CachedAccessibilityMapView)?.invalidateAccessibilitySnapshot()
            for annotation in mapView.annotations(in: mapView.visibleMapRect) {
                guard let point = annotation.base as? PointAnnotation,
                      let view = mapView.view(for: point) as? LabelAnnotationView else { continue }
                view.releaseInactiveTextView()
            }
            let center = TableLocation(longitude: mapView.centerCoordinate.longitude, latitude: mapView.centerCoordinate.latitude)
            DispatchQueue.main.async { [weak self] in self?.centerChanged(center) }
        }
        func update(_ map: MKMapView, points: [DialectPoint], fit: Int, fontSize: Double = 16, readingSize: Double = 16, revision: UUID? = nil) {
            attachedMap = map
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
            view.setDrawingActive(!releasedDrawingBuffers || drawingRect(mapView).contains(MKMapPoint(point.coordinate)))
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

// Idle annotations use tightly sized drawing layers. Native controls exist only for an
// actual interaction; every point and the complete selectable reading remain.
// Keep the name and reading backing stores tightly sized. A single bitmap for
// their union wastes transparent pixels at every point in a dense map.
private final class MapLabelCanvas: UIView {
    var text = NSAttributedString(string: "")
    var colors = [UIColor]()
    private let centered: Bool
    private let radius: CGFloat
    private let inset: CGFloat
    init(centered: Bool, radius: CGFloat, inset: CGFloat) {
        self.centered = centered; self.radius = radius; self.inset = inset
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false; contentMode = .redraw
        isUserInteractionEnabled = false; accessibilityElementsHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MapLabelCanvas, _: UITraitCollection) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: bounds, cornerRadius: radius).addClip()
        (colors.first ?? .clear).setFill(); context.fill(bounds)
        if colors.count > 1, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.midY), end: CGPoint(x: bounds.maxX, y: bounds.midY), options: [])
        }
        if centered {
            let size = text.size()
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        } else {
            text.draw(with: bounds.insetBy(dx: inset, dy: inset), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        context.restoreGState()
    }
}

private final class MapLabelElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

final class LabelAnnotationView: MKAnnotationView {
    private let nameCanvas = MapLabelCanvas(centered: true, radius: 5, inset: 0)
    private var readingCanvas: MapLabelCanvas?
    private var drawingActive = true
    private var button: UIButton?
    private var nameText = NSAttributedString(string: "")
    private var nameFrame = CGRect.zero
    private var colors = [UIColor]()
    private var buttonGradient: CAGradientLayer?
    private(set) var readingView: UITextView?
    private var renderedReading = NSAttributedString(string: "")
    private var previewText = NSAttributedString(string: "")
    private var readingFrame = CGRect.zero
    private var readingNeedsScroll = false
    private var lastReadingInteraction: CFTimeInterval = 0
    private var choose: (() -> Void)?
    private var previousReading: String?
    private var previousParts: [ToneDisplay.Part]?
    private var previousFontSize: Double?
    private var previousGlyph = ""
    private var cachedReadingRect = CGRect.zero
    private var glyphLabelKey = ""
    private var previousColor: String?
    private lazy var nameElement: MapLabelElement = {
        let element = MapLabelElement(accessibilityContainer: self)
        element.accessibilityTraits = .button
        element.activate = { [weak self] in self?.choose?(); return true }
        return element
    }()
    private lazy var readingElement: MapLabelElement = {
        let element = MapLabelElement(accessibilityContainer: self)
        element.accessibilityTraits = .staticText
        element.activate = { [weak self] in self?.readingText.becomeFirstResponder() ?? false }
        return element
    }()
    var nameButton: UIButton {
        if let button { return button }
        let value = UIButton(type: .system)
        value.titleLabel?.adjustsFontForContentSizeCategory = false
        value.setAttributedTitle(nameText, for: .normal)
        value.frame = nameFrame; value.backgroundColor = colors.first
        value.layer.cornerRadius = 5; value.clipsToBounds = true
        let gradient = CAGradientLayer()
        gradient.colors = colors.map(\.cgColor); gradient.isHidden = colors.count <= 1
        gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = value.bounds; value.layer.insertSublayer(gradient, at: 0)
        buttonGradient = gradient
        value.addTarget(self, action: #selector(openDetails), for: .touchUpInside)
        value.accessibilityLabel = nameElement.accessibilityLabel
        value.accessibilityIdentifier = nameElement.accessibilityIdentifier
        addSubview(value); button = value; nameCanvas.isHidden = true; updateAccessibility()
        return value
    }
    var readingText: UITextView {
        if let readingView { return readingView }
        let text = UITextView()
        text.adjustsFontForContentSizeCategory = false
        text.isEditable = false; text.isSelectable = true
        text.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        text.textContainer.lineFragmentPadding = 0
        text.textContainer.maximumNumberOfLines = 0
        text.textContainer.lineBreakMode = .byCharWrapping
        text.textColor = .label; text.backgroundColor = MapReadingAppearance.background
        text.layer.cornerRadius = 4
        text.attributedText = renderedReading
        text.frame = readingFrame; text.isScrollEnabled = readingNeedsScroll
        text.accessibilityIdentifier = readingElement.accessibilityIdentifier
        text.accessibilityLabel = readingElement.accessibilityLabel
        addSubview(text); readingView = text; readingCanvas?.isHidden = true
        if window != nil { MapTextGestureGate.install(above: self) }
        updateAccessibility()
        return text
    }
    private func updateAccessibility() {
        let name: Any = button.map { $0 as Any } ?? nameElement
        let reading: Any = readingView.map { $0 as Any } ?? readingElement
        accessibilityElements = readingFrame.isEmpty ? [name] : [reading, name]
        var parent = superview
        while let view = parent {
            if let map = view as? CachedAccessibilityMapView { map.invalidateAccessibilitySnapshot(); break }
            parent = view.superview
        }
    }
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        traitOverrides.preferredContentSizeCategory = .large
        backgroundColor = .clear; isOpaque = false
        isUserInteractionEnabled = true; isAccessibilityElement = false
        addSubview(nameCanvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setDrawingActive(_ active: Bool) {
        guard drawingActive != active else { return }
        drawingActive = active
        nameCanvas.isHidden = !active || button != nil
        readingCanvas?.isHidden = !active || readingView != nil
        if active {
            nameCanvas.setNeedsDisplay(); readingCanvas?.setNeedsDisplay()
        } else {
            // Reconstructible pixels only. Keep all annotations, complete text,
            // accessibility and an active native text selection intact.
            nameCanvas.layer.contents = nil; readingCanvas?.layer.contents = nil
        }
    }
    private func updateCanvases(redraw: Bool) {
        nameCanvas.text = nameText; nameCanvas.colors = colors; nameCanvas.frame = nameFrame
        nameCanvas.isHidden = !drawingActive || button != nil
        if readingFrame.isEmpty {
            readingCanvas?.removeFromSuperview(); readingCanvas = nil
        } else {
            if readingCanvas == nil {
                let canvas = MapLabelCanvas(centered: false, radius: 4, inset: 4)
                canvas.colors = [MapReadingAppearance.background]
                insertSubview(canvas, at: 0); readingCanvas = canvas
            }
            readingCanvas?.text = previewText; readingCanvas?.frame = readingFrame
            readingCanvas?.isHidden = !drawingActive || readingView != nil
        }
        if redraw { nameCanvas.setNeedsDisplay(); readingCanvas?.setNeedsDisplay() }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && readingView != nil { MapTextGestureGate.install(above: self) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        let selecting = readingView?.isFirstResponder == true
        guard bounds.contains(point) || selecting else { return nil }
        if !readingFrame.isEmpty, readingFrame.contains(point) || selecting {
            lastReadingInteraction = CACurrentMediaTime()
            let text = readingText
            if let hit = text.hitTest(convert(point, to: text), with: event) { return hit }
        }
        guard nameFrame.contains(point) else { return nil }
        let name = nameButton
        return name.hitTest(convert(point, to: name), with: event)
    }
    @objc private func openDetails() { choose?() }
    func releaseInactiveTextView() {
        guard let text = readingView, !text.isFirstResponder, text.selectedRange.length == 0, text.contentOffset == .zero,
              CACurrentMediaTime() - lastReadingInteraction > 2,
              !(text.gestureRecognizers ?? []).contains(where: { $0.state == .began || $0.state == .changed }) else { return }
        text.removeFromSuperview(); readingView = nil; readingCanvas?.isHidden = !drawingActive; updateAccessibility()
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        readingView?.resignFirstResponder(); readingView?.removeFromSuperview(); readingView = nil
        button?.removeFromSuperview(); button = nil; buttonGradient = nil
        nameCanvas.isHidden = !drawingActive; readingCanvas?.isHidden = !drawingActive; updateAccessibility()
    }
    func configure(_ point: DialectPoint, fontSize: Double, labelSize: Double = 16, choose: @escaping () -> Void) {
        self.choose = choose
        let glyph = GlyphStandard.current.rawValue
        let labelKey = point.name + "|" + String(labelSize) + "|" + glyph
        var changed = false
        nameElement.accessibilityLabel = point.name
        nameElement.accessibilityIdentifier = "map-name-" + point.id
        if glyphLabelKey != labelKey {
            glyphLabelKey = labelKey; changed = true
            let title = GlyphStandard.attributed(point.name, font: .systemFont(ofSize: labelSize))
            title.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: title.length))
            nameText = title; button?.setAttributedTitle(title, for: .normal)
        }
        button?.accessibilityLabel = point.name; button?.accessibilityIdentifier = nameElement.accessibilityIdentifier
        if previousColor != point.color {
            previousColor = point.color; changed = true
            colors = TableColors.hexes(point.color).map { TableColors.uiColor($0) }
            if colors.isEmpty { colors = [TableColors.uiColor("#008080")] }
            button?.backgroundColor = colors.first
            buttonGradient?.colors = colors.map(\.cgColor); buttonGradient?.isHidden = colors.count <= 1
        }
        let textChanged = previousReading != point.reading || previousParts != point.toneParts || previousFontSize != fontSize || previousGlyph != glyph
        if point.reading.isEmpty {
            if previousReading != nil { changed = true }
            previousReading = nil; previousParts = nil
            readingView?.removeFromSuperview(); readingView = nil
            renderedReading = NSAttributedString(string: ""); previewText = renderedReading
            cachedReadingRect = .zero
        } else if textChanged {
        let text = NSMutableAttributedString(string: "")
        let font = GlyphStandard.font(UIFont.systemFont(ofSize: fontSize))
        let parts = point.toneParts ?? [.init(id: 0, base: point.reading, pitch: "", tone: "", stacked: false)]
        for part in parts {
            text.append(NSAttributedString(string: part.base, attributes: [.font: font, .foregroundColor: UIColor.label]))
            if part.stacked {
                let tiny = GlyphStandard.font(UIFont.systemFont(ofSize: fontSize * 0.55))
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
        GlyphStandard.apply(to: text)
        renderedReading = text
            if let readingView {
                let selection = readingView.selectedRange
                readingView.attributedText = text
                if !contentChanged && NSMaxRange(selection) <= text.length { readingView.selectedRange = selection }
                if contentChanged { readingView.setContentOffset(.zero, animated: false) }
            }
            previousReading = point.reading; previousParts = point.toneParts; previousFontSize = fontSize; previousGlyph = glyph
            let range = (text.string as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(text.length, 1024)))
            previewText = text.attributedSubstring(from: range)
            cachedReadingRect = previewText.boundingRect(with: CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            changed = true
        }
        readingElement.accessibilityLabel = point.reading
        readingElement.accessibilityIdentifier = "map-reading-" + point.id
        readingView?.accessibilityLabel = point.reading; readingView?.accessibilityIdentifier = readingElement.accessibilityIdentifier
        let nameSize = nameText.size()
        let nameWidth = nameSize.width + 12, nameHeight = max(nameSize.height, CGFloat(labelSize) * 1.4)
        let readingWidth = point.reading.isEmpty ? 0 : min(268, ceil(cachedReadingRect.width) + 8)
        let readingHeight = point.reading.isEmpty ? 0 : min(180, ceil(cachedReadingRect.height) + 8)
        let size = CGSize(width: max(nameWidth, readingWidth), height: nameHeight + readingHeight)
        if bounds.size != size { changed = true }
        bounds = CGRect(origin: .zero, size: size)
        nameFrame = CGRect(x: (size.width - nameWidth) / 2, y: 0, width: nameWidth, height: nameHeight)
        readingFrame = point.reading.isEmpty ? .zero : CGRect(x: (size.width - readingWidth) / 2, y: nameHeight, width: readingWidth, height: readingHeight)
        readingNeedsScroll = renderedReading.length > previewText.length || ceil(cachedReadingRect.height) + 8 > readingHeight
        button?.frame = nameFrame; buttonGradient?.frame = button?.bounds ?? .zero
        readingView?.frame = readingFrame; readingView?.isScrollEnabled = readingNeedsScroll
        nameElement.accessibilityFrameInContainerSpace = nameFrame
        readingElement.accessibilityFrameInContainerSpace = readingFrame
        collisionMode = .rectangle
        updateAccessibility()
        updateCanvases(redraw: changed)
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
