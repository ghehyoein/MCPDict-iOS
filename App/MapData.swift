import Foundation

struct TableLocation: Codable, Hashable {
    let longitude: Double
    let latitude: Double
    var valid: Bool { longitude.isFinite && latitude.isFinite && (-180...180).contains(longitude) && (-90...90).contains(latitude) }
    static func parse(_ text: String) -> TableLocation? {
        let parts = text.replacingOccurrences(of: "，", with: ",").split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let lon = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let lat = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let point = TableLocation(longitude: lon, latitude: lat)
        return point.valid ? point : nil
    }
}

struct DialectPoint: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let longitude: Double
    let latitude: Double
    let color: String
    let reading: String
    static func make(_ table: TablePackage, grouping: TableGrouping, reading: String = "") -> DialectPoint? {
        guard let location = table.location, location.valid else { return nil }
        let rawColor = grouping == .dictionary ? table.dictionaryColor : table.atlasColor
        let color = rawColor?.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? rawColor! : "#008080"
        return DialectPoint(id: table.id, name: table.name, longitude: location.longitude, latitude: location.latitude, color: color, reading: reading)
    }
}

extension DictionaryRepository {
    // Read every result page; the map must not silently stop after the first 100.
    func mapReadings(_ character: String) throws -> [String: String] {
        guard character.count == 1 else { throw DictionaryFailure(message: "讀音地圖請輸入一個漢字") }
        var result = [String: Set<String>]()
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try search(character, mode: .character, language: "", offset: offset)
            for row in page { result[row.language, default: []].insert(row.pronunciation) }
            if page.count < 100 { break }
            offset += page.count
        }
        return result.mapValues { $0.sorted().joined(separator: " / ") }
    }
}
