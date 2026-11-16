import SwiftUI

struct AnalysisColorSwatch: View {
    let hex: String
    var body: some View {
        Circle().fill(TableColors.color(hex))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 2))
            .frame(width: 28, height: 28).padding(2)
    }
}

struct AnalysisColorEditor: View {
    let initial: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hex = ""
    @State private var invalid = false
    private var color: Binding<Color> {
        Binding(get: { TableColors.color(CustomLanguageSchemes.validColor(hex) ?? initial) }, set: { value in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(value).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        })
    }
    var body: some View {
        Form {
            HStack(spacing: 8) {
                Text(ui("方案顏色")).foregroundStyle(Color.primary).fixedSize()
                Spacer(minLength: 0)
                TextField("#RRGGBB", text: $hex).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .keyboardType(.asciiCapable).multilineTextAlignment(.trailing).frame(width: 88)
                    .minimumScaleFactor(0.7).lineLimit(1).accessibilityIdentifier("analysisColorHex")
                ColorPicker(ui("方案顏色"), selection: color, supportsOpacity: false).labelsHidden().frame(width: 32)
                Button(ui("保存")) {
                    guard let value = CustomLanguageSchemes.validColor(hex) else { invalid = true; return }
                    save(value); dismiss()
                }.fixedSize().buttonStyle(.borderless).accessibilityIdentifier("saveAnalysisColor")
            }
        }.navigationTitle(ui("方案顏色")).navigationBarTitleDisplayMode(.inline)
            .onAppear { hex = initial }
            .alert(ui("請輸入六位十六進制顏色碼。"), isPresented: $invalid) { Button(ui("好"), role: .cancel) {} }
    }
}
