import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage(AppTypography.mapNameKey) private var mapNameSize = 14.0
    @AppStorage(AppTypography.mapReadingKey) private var mapReadingSize = 17.0
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
                Section(ui("地圖字體大小")) {
                    mapSlider("語言點名稱", $mapNameSize)
                    mapSlider("讀音", $mapReadingSize)
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
    private func mapSlider(_ label: String, _ size: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(ui(label) + " · " + String(Int(size.wrappedValue))).font(.system(size: size.wrappedValue))
            Slider(value: size, in: 10...32, step: 1) { Text(ui(label)) }
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

