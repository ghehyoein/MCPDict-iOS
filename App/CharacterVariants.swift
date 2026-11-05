import Foundation

enum CharacterVariants {
    private final class Shard {
        let values: [String: [String]]
        init(_ values: [String: [String]]) { self.values = values }
    }
    private static let cache = NSCache<NSNumber, Shard>()
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
    static func expand(_ input: String) -> [String] {
        let originals = CharacterResults.characters(input)
        var seen = Set<String>()
        // Match Android DB.java and backend queryVariants: reverse field lookup only.
        return (originals + originals.flatMap(related)).filter { seen.insert($0).inserted }
    }
}
