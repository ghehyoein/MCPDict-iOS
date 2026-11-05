import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("mapTilerKey") private var mapTilerKey = ""
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
                Section {
                    SecureField("MapTiler API key", text: $mapTilerKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Link("建立 MapTiler 帳號／取得 key", destination: URL(string: "https://cloud.maptiler.com/account/keys/")!)
                    if !mapTilerKey.isEmpty { Button("清除 key", role: .destructive) { mapTilerKey = "" } }
                } header: { Text("地圖底圖") }
                footer: { Text("未填寫時使用系統地圖；填寫後使用 MapTiler 街道圖。key 僅保存在本機並傳送至 MapTiler，底圖需連網，服務用量以你的 MapTiler 方案為準。可將 Allowed User-Agent 設為 MCPDict-iOS/*。") }
            }.navigationTitle("設定")
        }
    }
}
