import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage(AppTypography.mapKey) private var mapSize = 16.0
    var body: some View {
        NavigationStack {
            Form {

                Section(ui("顯示語言")) {
                    option("简体中文", value: "hans", selection: $uiLanguage)
                    option("元來是正體ɵɤ̞ɵ(", value: "hant", selection: $uiLanguage)
                }
                Section(ui("字體大小")) {
                    sizeSlider("地圖語言點、分區及讀音", $mapSize, range: 10...32, identifier: "mapSizeSlider")
                    sizeSlider("其他介面", $fontSize, range: 14...26, identifier: "fontSizeSlider")
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
                Section(ui("界面外觀")) {
                    option(ui("跟隨系統"), value: "system", selection: $appearance)
                    option(ui("淺色"), value: "light", selection: $appearance)
                    option(ui("深色"), value: "dark", selection: $appearance)
                }
                MapSettingsSection()
            }.navigationTitle(ui("設定"))
        }
    }
    private func sizeSlider(_ label: String, _ size: Binding<Double>, range: ClosedRange<Double>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(ui(label) + " · " + String(Int(size.wrappedValue))).font(.system(size: size.wrappedValue))
            Slider(value: size, in: range, step: 1) { Text(ui(label)) }.accessibilityIdentifier(identifier)
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

