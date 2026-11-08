import Foundation

// Bound simultaneous requests and retained source data. A large table runs alone;
// its existing per-file size/hash validation still applies.
enum TableDownloadBatch {
    static func make(_ tables: [TablePackage], maximumCount: Int = 4, byteBudget: Int64 = 16 * 1024 * 1024) -> [[TablePackage]] {
        precondition(maximumCount > 0 && byteBudget > 0)
        var batches = [[TablePackage]](), batch = [TablePackage]()
        var bytes: Int64 = 0
        for table in tables {
            if !batch.isEmpty && (batch.count == maximumCount || bytes + table.size > byteBudget) {
                batches.append(batch); batch = []; bytes = 0
            }
            batch.append(table); bytes += table.size
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches
    }
}
