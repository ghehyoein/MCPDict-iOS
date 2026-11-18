import Foundation

enum CharacterVariants {
    private final class Shard {
        let values: [String: [String]]
        init(_ values: [String: [String]]) { self.values = values }
    }
    private static let cache = NSCache<NSNumber, Shard>()
    static func clearCache() { cache.removeAllObjects() }
    static func related(_ character: String) -> [String] {
        guard let scalar = character.unicodeScalars.first else { return [] }
        let index = Int(scalar.value % 16)
        let key = NSNumber(value: index)
        let shard: [String: [String]]
        if let existing = cache.object(forKey: key) { shard = existing.values }
        else {
            guard let url = Bundle.main.url(forResource: "variants-\(index)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
            shard = decoded; cache.setObject(Shard(decoded), forKey: key)
        }
        return shard[character] ?? []
    }
    // Used only by the dictionary and map pickers. STCharacters is from
    // osfans/MCPDict 911a151; Japanese forms reverse OpenCC v1.1.9 JPVariants.
    private static let traditionalPriority: [String: String] = {
        guard let url = Bundle.main.url(forResource: "traditional-priority", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()

    static func pickerChoices(_ input: String) -> [String] {
        let originals = CharacterResults.characters(input)
        var seen = Set(originals)
        var choices = originals
        for original in originals {
            let variants = related(original)
            let candidates = Set(variants)
            for character in (traditionalPriority[original] ?? "").map(String.init)
                where candidates.contains(character) && seen.insert(character).inserted {
                choices.append(character)
            }
            choices.append(contentsOf: variants.filter { seen.insert($0).inserted })
        }
        return choices
    }

    static func expand(_ input: String) -> [String] {
        let originals = CharacterResults.characters(input)
        var seen = Set<String>()
        // Match Android DB.java and backend queryVariants: reverse field lookup only.
        return (originals + originals.flatMap(related)).filter { seen.insert($0).inserted }
    }
}
