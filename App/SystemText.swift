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
    @Environment(\.font) private var font
    @Environment(\.dynamicTypeSize) private var dynamicType
    init(_ text: String, color: UIColor = .label, pointSize: CGFloat? = nil, weight: UIFont.Weight = .regular, serif: Bool = false, parts: [ToneDisplay.Part]? = nil) {
        self.text = text; self.color = color; self.pointSize = pointSize; self.weight = weight; self.serif = serif; self.parts = parts
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
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let value = parts.map { ToneAttributedText.make($0, font: resolvedFont, color: color) }
            ?? NSAttributedString(string: text, attributes: [.font: resolvedFont, .foregroundColor: color])
        if view.attributedText != value { view.attributedText = value }
        view.accessibilityLabel = text
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let natural = ceil(uiView.attributedText.size().width)
        let width = max(1, min(proposal.width ?? natural, natural))
        let measured = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }
}

enum ToneAttributedText {
    static func make(_ parts: [ToneDisplay.Part], font: UIFont, color: UIColor = .label) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        for part in parts {
            text.append(NSAttributedString(string: part.base, attributes: [.font: font, .foregroundColor: color]))
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
                text.append(NSAttributedString(string: part.pitch + part.tone, attributes: [.font: font, .foregroundColor: color]))
            }
        }
        return text
    }
}
