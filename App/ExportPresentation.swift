import SwiftUI
import Photos

// Each share has its own file, so concurrent exports cannot overwrite one another.
// Files remain available until the activity finishes or the sheet is dismissed.
enum ExportFiles {
    static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func prepare(_ data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MCPDict-exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent((filename as NSString).lastPathComponent)
        do { try data.write(to: file, options: .atomic); return file }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    static func remove(_ file: URL?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

private struct SharedExport: Identifiable {
    let id = UUID()
    let url: URL
}
private struct ExportActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let finished: (Error?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "exportActivitySheet"
        controller.completionWithItemsHandler = { _, _, _, error in finished(error) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
private struct ExportShareModifier: ViewModifier {
    @Binding var isPresented: Bool
    let filename: String
    let data: () throws -> Data
    let onError: (Error) -> Void
    @State private var item: SharedExport?
    @State private var file: URL?
    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, showing in
                guard showing else { return }
                do {
                    let url = try ExportFiles.prepare(data(), filename: filename)
                    file = url; item = SharedExport(url: url)
                } catch { isPresented = false; onError(error) }
            }
            .sheet(item: $item, onDismiss: {
                ExportFiles.remove(file); file = nil; isPresented = false
            }) { value in
                ExportActivitySheet(url: value.url) { error in
                    item = nil
                    if let error { onError(error) }
                }
            }
    }
}
extension View {
    func exportShareSheet(isPresented: Binding<Bool>, filename: String, data: @escaping () throws -> Data, onError: @escaping (Error) -> Void) -> some View {
        modifier(ExportShareModifier(isPresented: isPresented, filename: filename, data: data, onError: onError))
    }
}

enum PhotoExport {
    static func savePNG(_ data: Data) async throws {
        guard !data.isEmpty else { throw DictionaryFailure(message: ui("無法生成圖片")) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw DictionaryFailure(message: ui("無法儲存至相簿，請在系統設定中允許加入照片。"))
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "MCPDict-Sankey.png"
            options.uniformTypeIdentifier = "public.png"
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}
