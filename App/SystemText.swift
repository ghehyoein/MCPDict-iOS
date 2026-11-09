import SwiftUI
import UIKit

/// Read-only UIKit text retains the platform's selection handles and full edit menu.
/// No copy-only context menu or filtering of system/third-party edit actions is installed.
struct SystemText: UIViewRepresentable {
    let text: String
    var color: UIColor = .label
    var pointSize: CGFloat? = nil
    var weight: UIFont.Weight = .regular
    var serif = false
    var parts: [ToneDisplay.Part]? = nil
    var boldPrefix: String? = nil
    var smallerPitch = false
    var onTap: (() -> Void)? = nil
    @Environment(\.font) private var font
    @Environment(\.dynamicTypeSize) private var dynamicType
    init(_ text: String, color: UIColor = .label, pointSize: CGFloat? = nil, weight: UIFont.Weight = .regular, serif: Bool = false, parts: [ToneDisplay.Part]? = nil, boldPrefix: String? = nil, smallerPitch: Bool = false, onTap: (() -> Void)? = nil) {
        self.text = text; self.color = color; self.pointSize = pointSize; self.weight = weight; self.serif = serif; self.parts = parts; self.boldPrefix = boldPrefix; self.smallerPitch = smallerPitch; self.onTap = onTap
    }
    private var category: UIContentSizeCategory {
        switch dynamicType {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        default: return .accessibilityExtraExtraExtraLarge
        }
    }
    private var resolvedFont: UIFont {
        let style: UIFont.TextStyle
        switch font {
        case .some(.caption): style = .caption1
        case .some(.caption2): style = .caption2
        case .some(.footnote): style = .footnote
        case .some(.subheadline): style = .subheadline
        case .some(.headline): style = .headline
        case .some(.title): style = .title1
        case .some(.title2): style = .title2
        case .some(.title3): style = .title3
        default: style = .body
        }
        let size = pointSize ?? UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return serif ? UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) : base
    }
    func makeCoordinator() -> Coordinator { Coordinator(onTap) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
            tap.cancelsTouchesInView = false; tap.delegate = context.coordinator
            view.addGestureRecognizer(tap)
        }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.action = onTap
        let pitchFont: UIFont? = smallerPitch ? (pointSize.map { UIFont.systemFont(ofSize: $0 * 0.7) } ?? UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))) : nil
        let content = parts.map { ToneAttributedText.make($0, font: resolvedFont, color: color, pitchFont: pitchFont) }
            ?? NSAttributedString(string: text, attributes: [.font: resolvedFont, .foregroundColor: color])
        let value = NSMutableAttributedString(attributedString: content)
        if let prefix = boldPrefix, text.hasPrefix(prefix) {
            value.addAttribute(.font, value: UIFont.systemFont(ofSize: resolvedFont.pointSize, weight: .bold), range: NSRange(location: 0, length: (prefix as NSString).length))
        }
        if view.attributedText != value { view.attributedText = value }
        view.accessibilityLabel = text
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let natural = ceil(uiView.attributedText.size().width)
        let width = max(1, min(proposal.width ?? natural, natural))
        let measured = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: (() -> Void)?
        init(_ action: (() -> Void)?) { self.action = action }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView, view.selectedRange.length == 0 else { return }
            action?()
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }

}

enum ToneAttributedText {
    static func make(_ parts: [ToneDisplay.Part], font: UIFont, color: UIColor = .label, pitchFont: UIFont? = nil) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        for part in parts {
            let baseFont = part.italic ? UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? font.fontDescriptor, size: font.pointSize) : font
            text.append(NSAttributedString(string: part.base, attributes: [.font: baseFont, .foregroundColor: color]))
            if part.stacked {
                let tiny = UIFont.systemFont(ofSize: font.pointSize * 0.55)
                let attrs: [NSAttributedString.Key: Any] = [.font: tiny, .foregroundColor: color]
                let width = max((part.pitch as NSString).size(withAttributes: attrs).width, (part.tone as NSString).size(withAttributes: attrs).width)
                let attachment = NSTextAttachment()
                attachment.image = UIGraphicsImageRenderer(size: CGSize(width: max(1, width), height: font.pointSize * 1.35)).image { _ in
                    (part.pitch as NSString).draw(at: .zero, withAttributes: attrs)
                    (part.tone as NSString).draw(at: CGPoint(x: 0, y: font.pointSize * 0.65), withAttributes: attrs)
                }
                attachment.bounds = CGRect(x: 0, y: -font.pointSize * 0.25, width: width, height: font.pointSize * 1.35)
                text.append(NSAttributedString(attachment: attachment))
            } else {
                text.append(NSAttributedString(string: part.pitch, attributes: [.font: pitchFont ?? font, .foregroundColor: color]))
                text.append(NSAttributedString(string: part.tone, attributes: [.font: font, .foregroundColor: color]))
            }
        }
        return text
    }
}
