import Foundation

enum CharacterVariants {
    private static let cache = NSCache<NSNumber, NSDictionary>()
    static func related(_ character: String) -> [String] {
        guard let scalar = character.unicodeScalars.first else { return [] }
        let index = Int(scalar.value % 16)
        let key = NSNumber(value: index)
        let shard: [String: [String]]
        if let existing = cache.object(forKey: key) as? [String: [String]] { shard = existing }
        else {
            guard let url = Bundle.main.url(forResource: "variants-\(index)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
            shard = decoded; cache.setObject(decoded as NSDictionary, forKey: key)
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
