import SwiftUI

struct BookPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var multiple = false
    @State private var editing = false
    @State private var editID: UUID?
    @State private var name = ""
    @State private var deletion = Set<UUID>()
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(ui("選擇方式"), selection: $multiple) {
                        Text(ui("單選")).tag(false); Text(ui("多選")).tag(true)
                    }.pickerStyle(.segmented)
                    HStack {
                        Button(ui("全選")) { multiple = true; model.selectBooks(Set(model.notebook.books.map(\.id))) }
                        Spacer()
                        Button(ui("清空")) { model.selectBooks([]) }
                    }.buttonStyle(.borderless)
                }
                Section {
                    ForEach(model.notebook.books) { book in
                        HStack {
                            Button { toggle(book.id) } label: {
                                HStack { Image(systemName: model.notebook.selected.contains(book.id) ? "checkmark.square.fill" : "square"); Text(verbatim: book.title); Spacer() }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityValue(model.notebook.selected.contains(book.id) ? ui("已選") : ui("未選"))
                            Menu {
                                Button(ui("重新命名")) { editID = book.id; name = book.name; editing = true }
                                Button(ui("刪除"), role: .destructive) { requestDelete([book.id]) }
                            } label: { Image(systemName: "ellipsis.circle").padding(6) }
                            .accessibilityLabel(ui("管理") + book.title)
                        }
                    }
                    Button(ui("新建生字表"), systemImage: "plus") { editID = nil; name = ""; editing = true }
                    Button(ui("刪除所選生字表"), role: .destructive) { requestDelete(model.notebook.selected) }
                        .disabled(model.notebook.selected.isEmpty)
                } footer: { Text(ui("在字典點星號，會收藏到所有已選的生字表。")) }
                if editing { editor }
            }.navigationTitle(ui("生字表")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(ui("完成")) { dismiss() } }
            .onAppear { multiple = model.notebook.selected.count > 1 }
            .onChange(of: multiple) { _, value in
                if !value, model.notebook.selected.count > 1, let first = model.notebook.books.first(where: { model.notebook.selected.contains($0.id) }) { model.selectBooks([first.id]) }
            }
            .confirmationDialog(ui("刪除所選生字表？"), isPresented: $confirm, titleVisibility: .visible) {
                Button(ui("刪除") + "（" + String(deletion.count) + "）", role: .destructive) { model.deleteBooks(deletion) }
                Button(ui("取消"), role: .cancel) {}
            } message: { Text(ui("只屬於這些生字表的條目也會刪除；其他生字表中的條目會保留。")) }
        }
    }
    private var editor: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = model.notebook.books.contains { $0.id != editID && $0.name == trimmed }
        return Section {
            TextField(ui("生字表名稱"), text: $name)
            if duplicate { Text(ui("名稱已被使用")).foregroundStyle(.secondary) }
            HStack {
                Button(ui("儲存")) { model.setBookName(name, id: editID); editing = false }.disabled(trimmed.isEmpty || duplicate)
                Spacer()
                Button(ui("取消")) { editing = false }
            }.buttonStyle(.borderless)
        } header: { Text(ui(editID == nil ? "新建生字表" : "重新命名")) }
    }
    private func toggle(_ id: UUID) {
        if !multiple { model.selectBooks([id]); return }
        var selected = model.notebook.selected
        if !selected.insert(id).inserted { selected.remove(id) }
        model.selectBooks(selected)
    }
    private func requestDelete(_ ids: Set<UUID>) { deletion = ids; confirm = !ids.isEmpty }
}
