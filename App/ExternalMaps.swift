import SwiftUI
import MapKit

enum BaseMapStyle: String, CaseIterable, Identifiable {
    case standard = "standard", satellite = "satellite", hybrid = "hybrid"
    var id: String { rawValue }
    var title: String {
        switch self { case .standard: return "標準"; case .satellite: return "衛星"; case .hybrid: return "混合" }
    }
    var type: MKMapType {
        switch self { case .standard: return .standard; case .satellite: return .satellite; case .hybrid: return .hybrid }
    }
}

enum DeviceMapApp: String, CaseIterable, Identifiable {
    case apple, amap, baidu, google
    var id: String { rawValue }
    var title: String {
        switch self { case .apple: return "Apple 地圖"; case .amap: return "高德地圖"; case .baidu: return "百度地圖"; case .google: return "Google Maps" }
    }
    var scheme: String {
        switch self { case .apple: return "maps"; case .amap: return "iosamap"; case .baidu: return "baidumap"; case .google: return "comgooglemaps" }
    }
    @MainActor static var available: [DeviceMapApp] {
        allCases.filter { UIApplication.shared.canOpenURL(URL(string: $0.scheme + "://")!) }
    }
    func url(location: TableLocation, name: String) -> URL? {
        guard location.valid else { return nil }
        let lat = String(location.latitude), lon = String(location.longitude)
        var components = URLComponents()
        components.scheme = scheme
        let fields: [(String, String)]
        switch self {
        case .apple:
            components.host = ""; fields = [("ll", "\(lat),\(lon)"), ("q", name)]
        case .google:
            components.host = ""; fields = [("center", "\(lat),\(lon)"), ("q", "\(lat),\(lon)"), ("zoom", "14")]
        case .amap:
            components.host = "viewMap"
            fields = [("sourceApplication", "汉字音典"), ("poiname", name), ("lat", lat), ("lon", lon), ("dev", "1")]
        case .baidu:
            components.host = "map"; components.path = "/marker"
            fields = [("location", "\(lat),\(lon)"), ("title", name), ("content", name), ("coord_type", "wgs84"), ("src", "ios.ghehyoein.MCPDictIOS")]
        }
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url
    }
    static func shareURL(location: TableLocation, name: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"), URLQueryItem(name: "q", value: name)]
        return components.url!
    }
}

struct ExternalMapMenu: View {
    let location: TableLocation
    let name: String
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preferredMapApp") private var preferred = "apple"
    @State private var applications = [DeviceMapApp]()
    @State private var failure = false
    var body: some View {
        Menu {
            if let app = applications.first(where: { $0.rawValue == preferred }) {
                Button(ui("預設") + " · " + ui(app.title)) { open(app) }
                Divider()
            }
            ForEach(applications) { app in Button(ui(app.title)) { preferred = app.rawValue; open(app) } }
            ShareLink(item: DeviceMapApp.shareURL(location: location, name: name), subject: Text(name), message: Text("\(location.latitude),\(location.longitude)")) {
                Label(ui("其他 App／分享位置"), systemImage: "square.and.arrow.up")
            }
        } label: { Label(ui("在地圖 App 中開啟"), systemImage: "arrow.up.forward.app") }
        .onAppear { applications = DeviceMapApp.available }
        .onChange(of: scenePhase) { _, phase in if phase == .active { applications = DeviceMapApp.available } }
        .alert(ui("無法開啟所選地圖，請確認已安裝，或使用分享位置。"), isPresented: $failure) { Button(ui("好"), role: .cancel) {} }
    }
    private func open(_ app: DeviceMapApp) {
        guard let url = app.url(location: location, name: name) else { failure = true; return }
        UIApplication.shared.open(url, options: [:]) { success in if !success { failure = true } }
    }
}

struct MapSettingsSection: View {
    @AppStorage("baseMapStyle") private var baseMapStyle = "standard"
    @AppStorage("preferredMapApp") private var preferred = "apple"
    @State private var applications = [DeviceMapApp]()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Section(ui("地圖")) {
            Picker(ui("App 內底圖"), selection: $baseMapStyle) {
                ForEach(BaseMapStyle.allCases) { Text(ui($0.title)).tag($0.rawValue) }
            }
            if !applications.isEmpty {
                Picker(ui("開啟位置的預設 App"), selection: $preferred) {
                    ForEach(applications) { Text(ui($0.title)).tag($0.rawValue) }
                }
            }
            Text(ui("其他地圖可透過「分享位置」開啟，取決於該 App 的分享支援。外部地圖會另行開啟，不替換本頁的語言點圖層。"))
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { refresh() }.onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }
    private func refresh() {
        applications = DeviceMapApp.available
        if !applications.contains(where: { $0.rawValue == preferred }), let first = applications.first { preferred = first.rawValue }
    }
}
