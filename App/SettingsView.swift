import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section("介面外觀") {
                    Picker("黑白模式", selection: $appearance) {
                        Text("跟隨系統").tag("system")
                        Text("淺色（白色）").tag("light")
                        Text("深色（黑色）").tag("dark")
                    }.pickerStyle(.inline)
                }
            }.navigationTitle("設定")
        }
    }
}
