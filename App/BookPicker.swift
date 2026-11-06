import SwiftUI

struct BookPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var reading: Reading? = nil
    @State private var draft = Set<UUID>()
    private var selected: Set<UUID> { reading == nil ? model.notebook.selected : draft }
    private func select(_ ids: Set<UUID>) { if reading == nil { model.selectBooks(ids) } else { draft = ids } }
    @State private var editing = false
    @State private var editID: UUID?
    @State private var name = ""
    @State private var deletion = Set<UUID>()
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button(ui("全選")) { select(Set(model.notebook.books.map(\.id))) }
                        Spacer()
                        Button(ui("清空")) { select([]) }
                    }.buttonStyle(.borderless)
                }
                Section {
                    ForEach(model.notebook.books) { book in
                        HStack {
                            Button { toggle(book.id) } label: {
                                HStack { Image(systemName: selected.contains(book.id) ? "checkmark.square.fill" : "square"); Text(verbatim: book.title); Spacer() }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityValue(selected.contains(book.id) ? ui("已選") : ui("未選"))
                            Menu {
                                Button(ui("重新命名")) { editID = book.id; name = book.name; editing = true }
                            } label: { Image(systemName: "ellipsis.circle").padding(6) }
                            .accessibilityLabel(ui("管理") + book.title)
                        }
                    }
                    Button(ui("新建生字表"), systemImage: "plus") { editID = nil; name = ""; editing = true }
                } footer: { if reading != nil { Text(ui("點「完成」儲存勾選的生字表；不勾選任何表會取消收藏。")) } }
                if editing { editor }
            }.navigationTitle(ui("生字表")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ui("刪除"), role: .destructive) { requestDelete(selected) }.disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ui("完成")) { if let reading { model.assign(reading, to: draft) }; dismiss() }
                }
            }
            .onAppear { if let reading { draft = model.memberships(reading) } }
            .onChange(of: model.notebook.books.map(\.id)) { _, ids in draft.formIntersection(ids) }
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
        var selected = self.selected
        if !selected.insert(id).inserted { selected.remove(id) }
        select(selected)
    }
    private func requestDelete(_ ids: Set<UUID>) { deletion = ids; confirm = !ids.isEmpty }
}
