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
    var copyText: String? = nil
    var toneParts: [ToneDisplay.Part]? = nil
    static func make(_ table: TablePackage, grouping: TableGrouping, reading: String = "") -> DialectPoint? {
        guard let location = table.location, location.valid else { return nil }
        let rawColor = grouping == .dictionary ? table.dictionaryColor : table.atlasColor
        let values = TableColors.hexes(rawColor)
        let color = values.isEmpty ? "#008080" : values.joined(separator: ",")
        return DialectPoint(id: table.id, name: table.name, longitude: location.longitude, latitude: location.latitude, color: color, reading: reading)
    }
}

struct MapHandoff: Identifiable {
    let id = UUID()
    let character: String
    let result: MapSearchResult
    let names: Set<String>
}

struct MapSearchResult {
    struct Line: Hashable {
        let text: String
        let pronunciation: String
        let note: String
        var fullText: String { note.isEmpty ? text : text + "  " + note }
    }
    let mode: SearchMode
    let query: String
    var choices = [String]()
    var groups = [String: [String: [Line]]]()
}

extension DictionaryRepository {
    func mapSearch(_ query: String, mode: SearchMode, names: Set<String>, characterRange: CharacterSearchRange = .all) async throws -> MapSearchResult {
        var result = MapSearchResult(mode: mode, query: query)
        if mode == .character { result.choices = try await CharacterRangeIndex.shared.filter(CharacterVariants.expand(query), range: characterRange) }
        guard !names.isEmpty else { return result }
        let found = try searchAll(mode == .character ? result.choices.joined() : query, mode: mode, language: "", languages: Array(names))
        let rows = mode == .pronunciation ? try await CharacterRangeIndex.shared.filter(found, range: characterRange) : found
        var known = Set(result.choices)
        var seen = [String: [String: Set<MapSearchResult.Line>]]()
        for row in rows {
            for char in row.characters.filter({ !$0.isWhitespace }).map(String.init) {
                let key = mode == .pronunciation ? "" : char
                if mode == .note, known.insert(char).inserted { result.choices.append(char) }
                let line = MapSearchResult.Line(text: mode == .pronunciation ? char : row.pronunciation,
                                                pronunciation: row.pronunciation, note: mode == .note ? row.note : "")
                if seen[key, default: [:]][row.language, default: []].insert(line).inserted {
                    result.groups[key, default: [:]][row.language, default: []].append(line)
                }
            }
        }
        return result
    }
}

extension DictionaryRepository {
    func mapReadingsForVariants(_ variants: [String]) throws -> [String: [String: String]] {
        let characters = Set(variants.filter { $0.count == 1 })
        guard !characters.isEmpty else { return [:] }
        let rows = try searchAllCharacters(characters.sorted().joined(), language: "")
        var collected = [String: [String: Set<String>]]()
        for row in rows {
            for character in row.characters.split(whereSeparator: { $0.isWhitespace }).map(String.init) where characters.contains(character) {
                collected[character, default: [:]][row.language, default: []].insert(row.pronunciation)
            }
        }
        return collected.mapValues { $0.mapValues { $0.sorted().joined(separator: " / ") } }
    }
    // One complete query, without repeated OFFSET scans or a 100-result cutoff.
    func mapReadings(_ character: String) throws -> [String: String] {
        guard character.count == 1 else { throw DictionaryFailure(message: "讀音地圖請輸入一個漢字") }
        var result = [String: Set<String>]()
        let rows = try searchAllCharacters(character, language: "")
        for row in rows { result[row.language, default: []].insert(row.pronunciation) }
        return result.mapValues { $0.sorted().joined(separator: " / ") }
    }
}
