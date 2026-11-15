import SwiftUI

// Keep character-selector buttons tappable while applying the same missing-glyph
// fallback as selectable result text, including supplementary-plane characters.
struct GlyphChoiceText: View {
    let value: String
    @ScaledMetric(relativeTo: .body) private var size = 17.0
    @AppStorage("glyphStandard") private var standard = ""
    init(_ value: String) { self.value = value }
    var body: some View {
        Text(AttributedString(GlyphStandard.attributed(value, font: .systemFont(ofSize: size), standard: GlyphStandard(rawValue: standard) ?? .system)))
    }
}
