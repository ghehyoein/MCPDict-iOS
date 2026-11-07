import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage(AppTypography.mapKey) private var mapSize = 16.0
    @AppStorage(AppTypography.readingKey) private var readingSize = 16.0
    @State private var referenceSettings = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { DataView() } label: { Text(ui("字表下載")) }
                    Button(ui("字頭資料顯示")) { referenceSettings = true }.foregroundStyle(AppAccent.color)
                }
                FavoriteSettingsSection()


                Section(ui("顯示語言")) {
                    option("简体中文", value: "hans", selection: $uiLanguage)
                    option("元來是正體ɵɤ̞ɵ(", value: "hant", selection: $uiLanguage)
                }
                Section(ui("字體大小")) {
                    sizeSlider("地圖語言點", $mapSize, range: 5...25, identifier: "mapSizeSlider", sample: 0)
                    sizeSlider("地圖搜索結果", $readingSize, range: 5...25, identifier: "mapReadingSlider", sample: 1)
                    sizeSlider("顯示介面", $fontSize, range: 14...26, identifier: "fontSizeSlider", sample: 2)
                }
                Section(ui("聲調顯示")) {
                    HStack { SystemText(ui("聲調預覽：")); Spacer(); HStack(spacing: 0) { SystemText("好"); PronunciationView(raw: "hæ3", table: ToneDisplay.previewTable, scrollable: false) } }
                    Picker("", selection: $toneStyle) {
                        ForEach(ToneDisplay.styles, id: \.0) { Text(ui($0.1)).tag($0.0) }
                    }.pickerStyle(.inline).labelsHidden()
                    Picker(ui("調值樣式"), selection: $pitchStyle) {
                        Text(ui("曲線")).tag("curve"); Text(ui("數字")).tag("number"); Text(ui("隱藏")).tag("hidden")
                    }.pickerStyle(.menu)
                }
                Section(ui("界面外觀")) {
                    option(ui("跟隨系統"), value: "system", selection: $appearance)
                    option(ui("淺色"), value: "light", selection: $appearance)
                    option(ui("深色"), value: "dark", selection: $appearance)
                }
                MapSettingsSection()
                Section {
                    Button(ui("還原預設設定"), role: .destructive) { model.resetSettings() }
                        .foregroundStyle(.red).accessibilityIdentifier("resetSettings")
                }
            }.navigationTitle(ui("設定")).onAppear { mapSize = min(25, max(5, mapSize)) }
        }.sheet(isPresented: $referenceSettings) { ReferenceSettingsView().dynamicTypeSize(AppTypography.size(fontSize)) }
    }
    private func sizeSlider(_ label: String, _ size: Binding<Double>, range: ClosedRange<Double>, identifier: String, sample: Int) -> some View {
        VStack(alignment: .leading) {
            HStack {
                SystemText(ui(label), pointSize: CGFloat(fontSize))
                Spacer()
                if sample == 0 {
                    let table = model.availableTables.first { $0.name == "通東呂四" }
                    Button { model.tableDetail = table } label: {
                        LanguageBadge(name: "通東呂四", table: table).environment(\.mapLabelSize, mapSize)
                    }.buttonStyle(.plain).disabled(table == nil)
                } else if sample == 1 {
                    HStack(spacing: 0) { SystemText("好", pointSize: CGFloat(readingSize)); PronunciationView(raw: "hæ3", table: ToneDisplay.previewTable, pointSize: readingSize, scrollable: false) }
                } else { SystemText(ui("漢字音典"), pointSize: CGFloat(fontSize)) }
            }
            Slider(value: size, in: range) { Text(ui(label)) }.accessibilityIdentifier(identifier)
        }.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
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

