import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage("colorScheme") private var colorScheme = "atlas"
    var body: some View {
        NavigationStack {
            Form {

                Section(ui("顯示語言")) {
                    option("简体中文", value: "hans", selection: $uiLanguage)
                    option("元來是正體ɵɤ̞ɵ(", value: "hant", selection: $uiLanguage)
                }
                Section(ui("字體大小")) {
                    Slider(value: $fontSize, in: 14...26, step: 1) { Text(ui("字體大小")) }.accessibilityIdentifier("fontSizeSlider")
                    Text(ui("字體預覽") + " · 漢字音典 tɕiɔŋ ①③⑤⑦").font(.body)
                }
                Section(ui("聲調顯示")) {
                    Picker(ui("調類樣式"), selection: $toneStyle) {
                        ForEach(ToneDisplay.styles, id: \.0) { Text(ui($0.1)).tag($0.0) }
                    }.pickerStyle(.inline)
                    Picker(ui("調值樣式"), selection: $pitchStyle) {
                        Text(ui("曲線")).tag("curve")
                        Text(ui("數字")).tag("number")
                        Text(ui("隱藏")).tag("hidden")
                    }.pickerStyle(.segmented)
                }
                Section(ui("分區顏色")) {
                    Picker(ui("配色方案"), selection: $colorScheme) {
                        Text(ui("地圖集二分區")).tag("atlas")
                        Text(ui("音典分區")).tag("dictionary")
                    }
                }
                Section(ui("界面外觀")) {
                    option(ui("跟隨系統"), value: "system", selection: $appearance)
                    option(ui("淺色"), value: "light", selection: $appearance)
                    option(ui("深色"), value: "dark", selection: $appearance)
                }
                MapSettingsSection()
            }.navigationTitle(ui("設定"))
        }
    }
    private func option(_ title: String, value: String, selection: Binding<String>) -> some View {
        Button { selection.wrappedValue = value } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                if selection.wrappedValue == value { Image(systemName: "checkmark") }
            }.contentShape(Rectangle())
        }.accessibilityIdentifier(title)
    }
}

