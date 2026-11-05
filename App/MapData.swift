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
    var toneParts: [ToneDisplay.Part]? = nil
    static func make(_ table: TablePackage, grouping: TableGrouping, reading: String = "") -> DialectPoint? {
        guard let location = table.location, location.valid else { return nil }
        let rawColor = grouping == .dictionary ? table.dictionaryColor : table.atlasColor
        let values = TableColors.hexes(rawColor)
        let color = values.isEmpty ? "#008080" : values.joined(separator: ",")
        return DialectPoint(id: table.id, name: table.name, longitude: location.longitude, latitude: location.latitude, color: color, reading: reading)
    }
}

extension DictionaryRepository {
    // One complete query, without repeated OFFSET scans or a 100-result cutoff.
    func mapReadings(_ character: String) throws -> [String: String] {
        guard character.count == 1 else { throw DictionaryFailure(message: "讀音地圖請輸入一個漢字") }
        var result = [String: Set<String>]()
        let rows = try searchAllCharacters(character, language: "")
        for row in rows { result[row.language, default: []].insert(row.pronunciation) }
        return result.mapValues { $0.sorted().joined(separator: " / ") }
    }
}

