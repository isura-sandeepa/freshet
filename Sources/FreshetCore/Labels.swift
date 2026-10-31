import Foundation

/// Labels per torrent. libtorrent's resume data has no room for them, so the app keeps
/// this book in its own JSON file.
public struct LabelBook: Codable, Equatable, Sendable {
    public var assignments: [TorrentID: String] = [:]
    /// Labels created but not yet assigned to anything.
    public var extraNames: [String] = []

    public init() {}

    public var names: [String] {
        Set(assignments.values).union(extraNames)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func count(of label: String) -> Int {
        assignments.values.filter { $0 == label }.count
    }

    public mutating func assign(_ label: String?, to ids: [TorrentID]) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in ids {
            if let trimmed, !trimmed.isEmpty { assignments[id] = trimmed } else { assignments[id] = nil }
        }
        if let trimmed, !trimmed.isEmpty, !extraNames.contains(trimmed) { extraNames.append(trimmed) }
    }

    public mutating func forget(_ ids: [TorrentID]) {
        for id in ids { assignments[id] = nil }
    }

    public mutating func removeLabel(_ name: String) {
        assignments = assignments.filter { $0.value != name }
        extraNames.removeAll { $0 == name }
    }
}
