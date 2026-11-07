import SwiftUI

/// Wrap complete information fields, allowing a long field to wrap within its own width.
struct WrappingInformationLayout: Layout {
    var spacing: CGFloat = 8
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        var origins = [CGPoint]()
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? 320).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrangement(subviews, width: bounds.width).1
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + origins[index].x, y: bounds.minY + origins[index].y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
