import SwiftUI

struct SingleLanguageSelectionPanel: View {
    let tables: [TablePackage]
    @Binding var language: String
    @ObservedObject var state: LanguageSelectionState
    let entryID: String
    var opened: () -> Void = {}
    private var names: Binding<Set<String>> {
        Binding(get: { language.isEmpty ? [] : [language] }, set: { language = $0.sorted().first ?? "" })
    }
    var body: some View {
        LanguageSelectionPanel(tables: tables, names: names, state: state, entryID: entryID,
                               languageOnly: true, singleSelection: true)
            .onChange(of: state.expanded) { _, expanded in if expanded { opened() } }
    }
}
