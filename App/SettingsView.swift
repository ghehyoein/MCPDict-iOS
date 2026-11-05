import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    var body: some View {
        NavigationStack {
            Form {
                Section(ui("顯示語言")) {
                    Picker(ui("顯示語言"), selection: $uiLanguage) {
                        Text(verbatim: "简体中文").tag("hans")
                        Text(verbatim: "繁體中文").tag("hant")
                    }.pickerStyle(.inline)
                }
                Section(ui("介面外觀")) {
                    Picker(ui("黑白模式"), selection: $appearance) {
                        Text(ui("跟隨系統")).tag("system")
                        Text(ui("淺色（白色）")).tag("light")
                        Text(ui("深色（黑色）")).tag("dark")
                    }.pickerStyle(.inline)
                }
            }.navigationTitle(ui("設定"))
        }
    }
}
