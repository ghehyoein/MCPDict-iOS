import SwiftUI

struct PronunciationFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, points) = arrange(width: bounds.width, subviews: subviews)
        for (view, point) in zip(subviews, points) { view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(bounds.width, view.sizeThatFits(.unspecified).width), height: view.sizeThatFits(.unspecified).height)) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0, maximum: CGFloat = 0
        var points = [CGPoint]()
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += height + 4; height = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 8
            maximum = max(maximum, x - 8); height = max(height, size.height)
        }
        return (CGSize(width: min(width, maximum), height: y + height), points)
    }
}
